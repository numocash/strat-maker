import { type Fraction, createFraction } from "reverse-mirage";
import { keccak256 } from "viem";
import { encodePacked } from "viem/abi";
import { Q128 } from "./constants.js";
import type { Pair } from "./types.js";

/**
 * Convert fraction type to Q128 integer
 */
export const fractionToQ128 = (fraction: Fraction): bigint =>
  (fraction.numerator * Q128) / fraction.denominator;

/**
 * Convert Q128 integer to fraction type
 */
export const q128ToFraction = (q128: bigint): Fraction =>
  createFraction(q128, Q128);

export const getPairID = (pair: Pair) =>
  keccak256(
    encodePacked(
      ["address", "address", "uint8"],
      [pair.token0.address, pair.token1.address, pair.scalingFactor],
    ),
  );
