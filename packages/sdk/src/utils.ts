import { type Fraction, makeFraction } from "reverse-mirage";
import { Q128 } from "./constants.js";

/**
 * Convert fraction type to Q128 integer
 */
export const fractionToQ128 = (fraction: Fraction): bigint =>
  (fraction.numerator * Q128) / fraction.denominator;

/**
 * Convert Q128 integer to fraction type
 */
export const q128ToFraction = (q128: bigint): Fraction =>
  makeFraction(q128, Q128);
