import type { Pair } from "dry-powder-sdk";
import { useState } from "react";
import { createContainer } from "unstated-next";
import type { Address, Hex } from "viem";

const useEnvironmentInternal = () => {
  const [id, setID] = useState<Hex | undefined>(undefined);
  const [pair, setPair] = useState<Pair | undefined>(undefined);
  const [router, setRouter] = useState<Address | undefined>(undefined);
  const [permit, setPermit] = useState<Address | undefined>(undefined);
  return { id, setID, pair, setPair, router, setRouter, permit, setPermit };
};

export const { Provider: EnvironmentProvider, useContainer: useEnvironment } =
  createContainer(useEnvironmentInternal);
