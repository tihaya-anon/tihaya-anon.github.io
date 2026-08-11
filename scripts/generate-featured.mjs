#!/usr/bin/env node

import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";

const [pagePath, customSeed] = process.argv.slice(2);

if (!pagePath) {
  console.error("Usage: node scripts/generate-featured.mjs <content-bundle-directory> [seed]");
  process.exit(1);
}

const pageDirectory = resolve(pagePath);
const indexPath = ["index.md", "_index.md"]
  .map((fileName) => join(pageDirectory, fileName))
  .find(existsSync);
const outputPath = join(pageDirectory, "featured.svg");
const rootDirectory = resolve(dirname(new URL(import.meta.url).pathname), "..");

if (!indexPath) {
  console.error(`Expected index.md or _index.md in ${pageDirectory}`);
  process.exit(1);
}

function getColor(css, name) {
  const match = css.match(new RegExp(`--color-${name}:\\s*([0-9]+),\\s*([0-9]+),\\s*([0-9]+)`));
  if (!match) throw new Error(`Could not find --color-${name}`);
  return `#${match.slice(1).map((value) => Number(value).toString(16).padStart(2, "0")).join("")}`;
}

function hash(value) {
  let result = 2166136261;
  for (const character of value) {
    result ^= character.charCodeAt(0);
    result = Math.imul(result, 16777619);
  }
  return result >>> 0;
}

function randomGenerator(seed) {
  let state = seed;
  return () => {
    state += 0x6d2b79f5;
    let value = state;
    value = Math.imul(value ^ (value >>> 15), value | 1);
    value ^= value + Math.imul(value ^ (value >>> 7), value | 61);
    return ((value ^ (value >>> 14)) >>> 0) / 4294967296;
  };
}

const paletteSource = readFileSync(join(rootDirectory, "assets/css/schemes/blowfish.css"), "utf8");
const colors = [
  getColor(paletteSource, "primary-400"),
  getColor(paletteSource, "primary-600"),
  getColor(paletteSource, "secondary-300"),
  getColor(paletteSource, "secondary-600"),
];
const logoSource = readFileSync(join(rootDirectory, "assets/img/logo.svg"), "utf8");
const logoPath = logoSource.match(/<path[\s\S]*?\/>/)?.[0];

if (!logoPath) throw new Error("Could not extract the logo path");

const seed = customSeed ?? relative(rootDirectory, pageDirectory);
const random = randomGenerator(hash(seed));
const canvasWidth = 1200;
const canvasHeight = 630;
const logoSize = 100;
const logoCenter = 50;
const minimumVisibleArea = 0.6;
const flowerColor = colors[Math.floor(random() * colors.length)];
const flowerXRatio = random();
const flowerYRatio = random();
const flowerScale = Number((2.5 + random() * 1.3).toFixed(2));
const flowerRotation = random() * 360;
const minimumVisiblePerAxis = Math.sqrt(minimumVisibleArea);
const flowerInset = Math.ceil(logoSize * flowerScale * (minimumVisiblePerAxis - 0.5) * 10) / 10;
const flowerX = flowerInset + flowerXRatio * (canvasWidth - flowerInset * 2);
const flowerY = flowerInset + flowerYRatio * (canvasHeight - flowerInset * 2);
const petals = logoPath.replace("currentColor", flowerColor);
const lines = Array.from({ length: 5 + Math.floor(random() * 4) }, () => {
  const x = -80 + random() * 1280;
  const y = -80 + random() * 790;
  const angle = Math.floor(random() * 4) * 45 + 22.5;
  const length = 110 + random() * 230;
  const color = colors[Math.floor(random() * colors.length)];
  const opacity = (0.34 + random() * 0.26).toFixed(2);
  const width = 9 + Math.floor(random() * 8);
  return `<line x1="${x.toFixed(1)}" y1="${y.toFixed(1)}" x2="${(x + length).toFixed(1)}" y2="${y.toFixed(1)}" transform="rotate(${angle} ${x.toFixed(1)} ${y.toFixed(1)})" stroke="${color}" stroke-width="${width}" stroke-linecap="round" opacity="${opacity}"/>`;
}).join("\n  ");

const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${canvasWidth}" height="${canvasHeight}" viewBox="0 0 ${canvasWidth} ${canvasHeight}" role="img" aria-label="Abstract geometric blog cover">
  <g fill="none">${lines}</g>
  <g transform="translate(${flowerX.toFixed(1)} ${flowerY.toFixed(1)}) rotate(${flowerRotation.toFixed(1)}) scale(${flowerScale.toFixed(2)}) translate(-${logoCenter} -${logoCenter})">${petals}</g>
</svg>`;

writeFileSync(outputPath, svg);
console.log(`Generated ${outputPath} with seed ${seed}`);
