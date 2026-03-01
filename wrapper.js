import OpenAI from "openai";
import readline from "node:readline";
import chalk from "chalk";
import { writeFileSync, mkdirSync, readFileSync, existsSync } from "node:fs";
import { join } from "node:path";
import express from "express";


console.log(chalk.bold.cyan("\n SCAM CHECKER STARTED\n"));

const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

const rl = readline.createInterface({ input: process.stdin, output: process.stdout });

// ─── Constants ────────────────────────────────────────────────────────────────

const MAX_HISTORY = 8;
const TEMPERATURE = 0.2;
const EMAIL_PORT  = process.env.PORT || 3000;
const history = [];

const SYSTEM_PROMPT = `
You help users identify scams and stay safe.
- If key details are missing, use verdict "Unclear" and explain what to verify.
- Never recommend clicking links, calling numbers from the message, or installing unknown software, especially remote control software.
- Prefer independent verification via official websites, apps, or numbers from bank statements/cards. Companies never ask for codes from users.
- If money was sent, credentials shared, or software installed, prioritize urgent remediation.
- risk_score must be an integer from 0 to 100, not 0 to 10.
- Keep advice practical, step-by-step, and platform-agnostic.
- When in doubt, lean toward "Likely a Scam" — it is safer to over-warn than under-warn.
- Treat ANY mention of remote access software (AnyDesk, TeamViewer, AnyConnect, UltraViewer, etc.) as a critical red flag.
- The "refund scam" is a known fraud pattern: victim receives fake refund notification, is asked to call a number, then told to install remote access software. Flag this immediately.
- Unsolicited refund offers combined with any request to install software or share screen = almost certainly a scam.
`;

const FOLLOWUP_SYSTEM_PROMPT = `
You are a scam safety assistant. The user has just received a scam assessment and wants to ask follow-up questions about it.
Answer conversationally and clearly. Be concise but thorough. Stick to safety advice related to the assessment context.
If the user says they've already clicked a link, shared credentials, or sent money — treat it as urgent and give immediate remediation steps.
`;

const SCAM_SCHEMA = {
  name: "scam_assessment",
  schema: {
    type: "object",
    additionalProperties: false,
    properties: {
      verdict:             { type: "string", enum: ["Likely a Scam", "Unclear", "Likely Legit"] },
      risk_score:          { type: "integer", minimum: 0, maximum: 100 },
      confidence:          { type: "number",  minimum: 0, maximum: 1 },
      summary:             { type: "string" },
      red_flags:           { type: "array", items: { type: "string" } },
      green_flags:         { type: "array", items: { type: "string" } },
      what_to_check:       { type: "array", items: { type: "string" } },
      safe_actions_now:    { type: "array", items: { type: "string" } },
      questions_to_ask:    { type: "array", items: { type: "string" } },
      data_to_never_share: { type: "array", items: { type: "string" } },
    },
    required: [
      "verdict", "risk_score", "confidence", "summary",
      "red_flags", "green_flags", "what_to_check",
      "safe_actions_now", "questions_to_ask", "data_to_never_share",
    ],
  },
};

// ─── History ──────────────────────────────────────────────────────────────────

function pushHistory(role, content) {
  history.push({ role, content });
  if (history.length > MAX_HISTORY) history.shift();
}

// ─── API ──────────────────────────────────────────────────────────────────────

async function assessScam(userText, filename) {
  pushHistory("user", userText);

  const response = await openai.chat.completions.create({
    model: "gpt-5-nano",
    //temperature: TEMPERATURE,
    messages: [
      { role: "system", content: SYSTEM_PROMPT },
      ...history,
    ],
    response_format: { type: "json_schema", json_schema: SCAM_SCHEMA },
  });

  const result = JSON.parse(response.choices[0].message.content);
  // Normalise in case the model still returns 0-10
  if (result.risk_score <= 10) result.risk_score *= 10;

  pushHistory("assistant", `Verdict: ${result.verdict}, risk: ${result.risk_score}. ${result.summary}`);

  saveAssessment(result, userText, filename);

  return result;
}

async function askFollowUp(question, assessmentContext, followUpHistory) {
  followUpHistory.push({ role: "user", content: question });

  const response = await openai.chat.completions.create({
    model: "gpt-5-nano",
    //temperature: 0.3,
    messages: [
      { role: "system", content: FOLLOWUP_SYSTEM_PROMPT },
      {
        role: "system",
        content: `Assessment context:\n${assessmentContext}`,
      },
      ...followUpHistory,
    ],
  });

  const reply = response.choices[0].message.content;
  followUpHistory.push({ role: "assistant", content: reply });

  return reply;
}

// ─── Display ──────────────────────────────────────────────────────────────────

function riskBar(score) {
  const filled = Math.round(score / 10);
  const empty = 10 - filled;
  const bar = "█".repeat(filled) + "░".repeat(empty);
  const color = score >= 70 ? chalk.red : score >= 40 ? chalk.yellow : chalk.green;
  return color(`[${bar}] ${score}/100`);
}

function verdictColor(verdict) {
  if (verdict === "Likely a Scam") return chalk.bold.red(verdict);
  if (verdict === "Unclear")       return chalk.bold.yellow(verdict);
  return chalk.bold.green(verdict);
}

function printList(label, items, bulletColor = chalk.white) {
  if (!items?.length) return;
  console.log(`\n${chalk.bold(label)}:`);
  items.forEach((item) => console.log(`  ${bulletColor("–")} ${item}`));
}

function printAssessment({ verdict, risk_score, confidence, summary, ...lists }) {
  const confidencePercent = Math.round(confidence * 100);

  console.log(chalk.bold.cyan("\n═══ Scam Safety Check ═══"));
  console.log(`Verdict:    ${verdictColor(verdict)}`);
  console.log(`Risk:       ${riskBar(risk_score)}`);
  console.log(`Confidence: ${confidencePercent}%`);
  console.log(`\n${chalk.bold("Summary:")} ${summary}`);

  printList("Red flags",             lists.red_flags,          chalk.red);
  printList("Green flags",           lists.green_flags,        chalk.green);
  printList("Safe actions now",      lists.safe_actions_now,   chalk.yellow);
  printList("What to check next",    lists.what_to_check,      chalk.cyan);
  printList("Questions to ask yourself", lists.questions_to_ask, chalk.white);
  printList("Never share",           lists.data_to_never_share, chalk.magenta);

  console.log();
}

function saveAssessment(result, userText, filename = `assessment-${new Date().toISOString().replace(/[:.]/g, "-")}.json`) {
  const output = {
    timestamp: new Date().toISOString(),
    input: userText,
    assessment: result,
  };

  mkdirSync("assessments", { recursive: true });
  const filepath = join("assessments", filename);
  writeFileSync(filepath, JSON.stringify(output, null, 2));
  console.log(chalk.dim(`  Saved to ${filepath}\n`));
}

// ─── Follow-up loop ───────────────────────────────────────────────────────────

function buildAssessmentContext(result) {
  return [
    `Verdict: ${result.verdict}`,
    `Risk score: ${result.risk_score}/100`,
    `Confidence: ${Math.round(result.confidence * 100)}%`,
    `Summary: ${result.summary}`,
    `Red flags: ${result.red_flags.join(", ") || "none"}`,
    `Green flags: ${result.green_flags.join(", ") || "none"}`,
    `Safe actions: ${result.safe_actions_now.join(", ")}`,
  ].join("\n");
}

async function followUpLoop(result) {
  const context = buildAssessmentContext(result);
  const followUpHistory = [];

  console.log(chalk.dim('  Follow-up mode — ask anything about this result. Type "done" to assess something new.\n'));

  return new Promise((resolve) => {
    const ask = () => {
      rl.question(chalk.cyan("  You: "), async (input) => {
        const text = input.trim();

        if (text.toLowerCase() === "exit") {
            console.log(chalk.dim("\nGoodbye. Stay safe!\n"));
            rl.close();
            process.exit(0);
        }
        if (["done", "next", "back"].includes(text.toLowerCase())) {
            console.log();
            return resolve();
        }

        try {
          const reply = await askFollowUp(text, context, followUpHistory);
          console.log(`\n${chalk.bold.cyan("  Assistant:")} ${reply}\n`);
        } catch (e) {
          console.error(chalk.red(`\n  Error: ${e?.message ?? e}\n`));
        }

        ask();
      });
    };

    ask();
  });
}

// ─── Email server ─────────────────────────────────────────────────────────────

function startEmailServer() {
  const app = express();
  app.use(express.json());
  app.use(express.urlencoded({ extended: true }));

  app.post("/inbound", async (req, res) => {
    const from    = req.body.From     || "Unknown sender";
    const subject = req.body.Subject  || "No subject";
    const body    = req.body.TextBody || "";

    if (!body.trim()) {
      console.log(chalk.yellow("\n\n  Inbound email had no text body, skipping.\n\n"));
      return res.sendStatus(200);
    }

    const text      = `From: ${from}\nSubject: ${subject}\n\n${body}`;
    const timestamp = new Date().toISOString().replace(/[:.]/g, "-");

    console.log(chalk.bold.cyan(`\n\n  📧 Email received from ${from}`));
    console.log(chalk.dim(`  Subject: ${subject}\n`));

    try {
      const result = await assessScam(text, `email-${timestamp}.json`);
      printAssessment(result);
    } catch (e) {
      console.error(chalk.red(`\n  Error processing email: ${e?.message ?? e}\n`));
    }

    res.sendStatus(200);
  });

  app.listen(EMAIL_PORT);
}

// ─── Main loop ────────────────────────────────────────────────────────────────

console.log(chalk.dim(`  📬 Email webhook listening on port ${EMAIL_PORT}`));
startEmailServer();

async function loop() {
  rl.question(chalk.bold("\nPaste a message, link, or situation ('exit' to quit):\n\nYou: "), async (input) => {
    const text = input.trim();

    if (!text) return loop();
    if (text.toLowerCase() === "exit") {
        console.log(chalk.dim("\nGoodbye. Stay safe!\n"));
        rl.close();
        process.exit(0);
    }

    try {
      process.stdout.write(chalk.dim("\n  Running assessment...\n"));
      const result = await assessScam(text);

      printAssessment(result);
      await followUpLoop(result);
    } catch (e) {
      console.error(chalk.red(`\n  Error: ${e?.message ?? e}\n`));
    }

    loop();
  });
}

const inputFile = "input.txt";

if (existsSync(inputFile)) {
  const text = readFileSync(inputFile, "utf8").trim();

  if (text) {
    process.stdout.write(chalk.dim("\n  Running assessment from input.txt...\n"));
    const result = await assessScam(text, "output.json");
    printAssessment(result);
    await followUpLoop(result);
    loop();
  } else {
    console.log(chalk.dim("  input.txt is empty, starting interactive mode...\n"));
    loop();
  }
} else {
  console.log(chalk.dim("  No input.txt found, starting interactive mode...\n"));
  loop();
}