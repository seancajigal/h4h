import OpenAI from "openai";
import readline from "node:readline";

console.log("PROGRAM STARTED");

const openai = new OpenAI({ 
    apiKey: process.env.OPENAI_API_KEY });

const rl = readline.createInterface({ 
    input: process.stdin, 
    output: process.stdout });

// ─── Constants ────────────────────────────────────────────────────────────────

const MAX_HISTORY = 8;
const history = [];

const SYSTEM_PROMPT = `
You help users identify scams and stay safe.
- If key details are missing, use verdict "Unclear" and explain what to verify.
- Never recommend clicking links, calling numbers from the message, or installing unknown software, especially remote control software.
- Prefer independent verification via official websites, apps, or numbers from bank statements/cards, remember companies never ask for codes from users.
- If money was sent, credentials shared, or software installed, prioritize urgent remediation.
- Keep advice practical, step-by-step, and platform-agnostic.
- Risk score is between 0 (not a scam) and 100 (definitely a scam), confidence is between 0 and 1.
`;

const SCAM_SCHEMA = {
  name: "scam_assessment",
  schema: {
    type: "object",
    additionalProperties: false,
    properties: {
      verdict:            { type: "string", enum: ["Likely a Scam", "Unclear", "Likely Legit"] },
      risk_score:         { type: "integer", minimum: 0, maximum: 100 },
      confidence:         { type: "number",  minimum: 0, maximum: 1 },
      summary:            { type: "string" },
      red_flags:          { type: "array", items: { type: "string" } },
      green_flags:        { type: "array", items: { type: "string" } },
      what_to_check:      { type: "array", items: { type: "string" } },
      safe_actions_now:   { type: "array", items: { type: "string" } },
      questions_to_ask:   { type: "array", items: { type: "string" } },
      data_to_never_share:{ type: "array", items: { type: "string" } },
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

async function assessScam(userText) {
  pushHistory("user", userText);

  const response = await openai.chat.completions.create({
    model: "gpt-5-nano",
    //temperature: 0.2,
    messages: [
      { role: "system", content: SYSTEM_PROMPT },
      ...history,
    ],
    response_format: { type: "json_schema", json_schema: SCAM_SCHEMA },
  });

  const result = JSON.parse(response.choices[0].message.content);

  pushHistory("assistant", `Verdict: ${result.verdict}, risk: ${result.risk_score}. ${result.summary}`);

  return result;
}

// ─── Display ──────────────────────────────────────────────────────────────────

function printList(label, items) {
  if (!items?.length) return;
  console.log(`\n${label}:`);
  items.forEach((item) => console.log(`  - ${item}`));
}

function printAssessment({ verdict, risk_score, confidence, summary, ...lists }) {
  const confidencePercent = Math.round(confidence * 100);
  console.log("\n=== Scam Safety Check ===");
  console.log(`Verdict: ${verdict}  |  Risk: ${risk_score}/100  |  Confidence: ${confidencePercent}%`);
  console.log(`\nSummary: ${summary}`);

  printList("Red flags",          lists.red_flags);
  printList("Green flags",        lists.green_flags);
  printList("Safe actions now",   lists.safe_actions_now);
  printList("What to check next", lists.what_to_check);
  printList("Questions to ask youself",   lists.questions_to_ask);
  printList("Never share",        lists.data_to_never_share);
}

// ─── Main loop ────────────────────────────────────────────────────────────────

function loop() {
  rl.question("\nYou ('exit' to quit): ", async (input) => {
    const text = input.trim();

    if (!text) return loop();
    if (text.toLowerCase() === "exit") return rl.close();

    try {
      printAssessment(await assessScam(text));
    } catch (e) {
      console.error("\nError:", e?.message ?? e);
    }

    loop();
  });
}

loop();