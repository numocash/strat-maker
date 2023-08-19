import { defineConfig } from "@wagmi/cli";
import { foundry } from "@wagmi/cli/plugins";

export default defineConfig({
  out: "src/generated.ts",
  contracts: [],
  plugins: [
    foundry({
      project: "node_modules/dry-powder/",
    }),
    foundry({
      project: "node_modules/ilrta-evm/",
      include: ["Permit3"],
    }),
  ],
});
