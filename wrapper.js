import OpenAI from "openai";
import readline from "readline";

console.log("PROGRAM STARTED");

const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
});

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
});

export async function fetchGPTResponse(prompt) {
  const response = await openai.chat.completions.create({
    model: "gpt-4o-mini",
    messages: [
      {
        role: "system",
        content: "You are an assistant that helps users identify scams and avoid them.",
      },
      {
        role: "user",
        content: `Determine whether the following is a scam: ${prompt}.
          Respond in JSON using this format:
          {
            "Is this a scam?": true/false,
            "Reason why": "A brief explanation of why it is or isn't a scam."
          }`,
      },
    ],
  });

  return response.choices[0].message.content;
}

async function ask(prompt) {
  const response = await openai.chat.completions.create({
    model: "gpt-4o-mini",
    messages: [{ role: "user", content: prompt }],
  });

  console.log("\nAI:", response.choices[0].message.content);
}

function loop() {
  rl.question("You: ", async (input) => {
    if (input.toLowerCase() === "exit") {
      rl.close();
      return;
    }
    await ask(input);
    loop();
  });
}

loop();