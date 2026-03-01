import OpenAI from "openai";
import readline from "node:readline";
import chalk from "chalk";
import { writeFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";


console.log(chalk.bold.cyan("\n SCAM CHECKER STARTED\n"));

const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

const rl = readline.createInterface({ input: process.stdin, output: process.stdout });

// ─── Constants ────────────────────────────────────────────────────────────────

const MAX_HISTORY = 8;
const TEMPERATURE = 0.2;
const history = [];

const SYSTEM_PROMPT = `
You help users identify scams and stay safe.
- If key details are missing, use verdict "Unclear" and explain what to verify.
- Never recommend clicking links, calling numbers from the message, or installing unknown software, especially remote control software.
- Prefer independent verification via official websites, apps, or numbers from bank statements/cards. Companies never ask for codes from users.
- If money was sent, credentials shared, or software installed, prioritize urgent remediation.
- risk_score must be an integer from 0 to 100, not 0 to 10.
- Keep advice practical, step-by-step, and platform-agnostic.
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

// ─── Pre-screening ────────────────────────────────────────────────────────────

// Quick cheap check before running the full structured assessment.
// Returns true if the input looks scam-related, false if it's off-topic.
async function isScamRelated(text) {
  const response = await openai.chat.completions.create({
    model: "gpt-5-nano",
    //temperature: 0,
    //max_completion_tokens: 5,
    messages: [
      {
        role: "system",
        content: `Reply only "yes" or "no". Is this message something a user might want checked for being a scam, phishing, fraud, or social engineering?`,
      },
      { role: "user", content: text },
    ],
  });
  const answer = response.choices[0].message.content.trim().toLowerCase();
  return answer.startsWith("yes");
}

// ─── API ──────────────────────────────────────────────────────────────────────

async function assessScam(userText) {
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

  saveAssessment(result, userText);

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

function saveAssessment(result, userText) {
  const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
  const output = {
    timestamp: new Date().toISOString(),
    input: userText,
    assessment: result,
  };

  mkdirSync("assessments", { recursive: true });
  const filename = join("assessments", `assessment-${timestamp}.json`);
  writeFileSync(filename, JSON.stringify(output, null, 2));
  console.log(chalk.dim(`  Saved to ${filename}\n`));
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

        if (!text) return ask();
        if (["done", "next", "back", "exit"].includes(text.toLowerCase())) {
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

// ─── Main loop ────────────────────────────────────────────────────────────────

async function loop() {
  rl.question(chalk.bold("\nPaste a message, link, or situation ('exit' to quit):\n\nYou: "), async (input) => {
    const text = input.trim();

    if (!text) return loop();
    if (text.toLowerCase() === "exit") {
      console.log(chalk.dim("\nGoodbye. Stay safe!\n"));
      return rl.close();
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

loop();