import { defineConfig } from "@wagmi/cli";
import { foundry } from "@wagmi/cli/plugins";

export default defineConfig({
  out: "src/generated.ts",
  contracts: [],
  plugins: [
    foundry({
      project: "node_modules/dry-powder/",
      include: [
        "Engine.sol/**",
        "Router.sol/**",
        "Pairs.sol/**",
        "Positions.sol/**",
        "ILRTA.sol/**",
        "Permit3.sol/**",
        "MockERC20.sol/**",
      ],
    }),
  ],
});
