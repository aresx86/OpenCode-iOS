import { deflateSync, inflateSync } from 'node:zlib'
import { writeFileSync, readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const SRC = 'C:/Users/18610/GOHI_workspace/AI_workspace/OpenCode-HarmonyOS/AppScope/resources/base/media/app_icon.png'
const OUT = join(dirname(fileURLToPath(import.meta.url)), '../Sources/Resources/Assets.xcassets/AppIcon.appiconset/icon_1024.png')
const TARGET = 1024

const buf = readFileSync(SRC)

// --- decode PNG ---
if (buf.readUInt32BE(0) !== 0x89504e47) throw new Error('not a png')
const width = buf.readUInt32BE(16)
const height = buf.readUInt32BE(20)
const bitDepth = buf[24]
const colorType = buf[25]
if (bitDepth !== 8 || (colorType !== 6 && colorType !== 2)) {
  throw new Error(`unsupported png: bitDepth=${bitDepth} colorType=${colorType}`)
}
const bpp = colorType === 6 ? 4 : 3

let pos = 8
const idatParts = []
while (pos + 8 <= buf.length) {
  const len = buf.readUInt32BE(pos)
  const type = buf.toString('ascii', pos + 4, pos + 8)
  if (type === 'IDAT') {
    idatParts.push(buf.subarray(pos + 8, pos + 8 + len))
  }
  if (type === 'IEND') break
  pos += 12 + len
}
const raw = inflateSync(Buffer.concat(idatParts))

const stride = width * bpp
const pixels = Buffer.alloc(height * stride)
{
  let p = 0
  const prev = Buffer.alloc(stride)
  for (let y = 0; y < height; y++) {
    const filter = raw[p++]
    const line = raw.subarray(p, p + stride)
    p += stride
    const cur = pixels.subarray(y * stride, (y + 1) * stride)
    for (let x = 0; x < stride; x++) {
      const a = x >= bpp ? cur[x - bpp] : 0
      const b = prev[x]
      const c = x >= bpp ? prev[x - bpp] : 0
      const v = line[x]
      let out
      switch (filter) {
        case 0: out = v; break
        case 1: out = v + a; break
        case 2: out = v + b; break
        case 3: out = v + ((a + b) >> 1); break
        case 4: {
          const pa = Math.abs(b - c)
          const pb = Math.abs(a - c)
          const pc = Math.abs(a + b - 2 * c)
          const pred = pa <= pb && pa <= pc ? a : (pb <= pc ? b : c)
          out = v + pred
          break
        }
        default: throw new Error('bad filter ' + filter)
      }
      cur[x] = out & 0xff
    }
    prev.set(cur)
  }
}

// to RGBA
const rgba = Buffer.alloc(width * height * 4)
if (bpp === 4) {
  rgba.set(pixels)
} else {
  for (let i = 0; i < width * height; i++) {
    rgba[i * 4] = pixels[i * 3]
    rgba[i * 4 + 1] = pixels[i * 3 + 1]
    rgba[i * 4 + 2] = pixels[i * 3 + 2]
    rgba[i * 4 + 3] = 255
  }
}

// --- bilinear resize to TARGET x TARGET ---
const out = Buffer.alloc(TARGET * TARGET * 4)
for (let y = 0; y < TARGET; y++) {
  const sy = Math.min(Math.max((y + 0.5) * height / TARGET - 0.5, 0), height - 1)
  const y0 = Math.floor(sy)
  const y1 = Math.min(y0 + 1, height - 1)
  const fy = sy - y0
  for (let x = 0; x < TARGET; x++) {
    const sx = Math.min(Math.max((x + 0.5) * width / TARGET - 0.5, 0), width - 1)
    const x0 = Math.floor(sx)
    const x1 = Math.min(x0 + 1, width - 1)
    const fx = sx - x0
    for (let ch = 0; ch < 4; ch++) {
      const p00 = rgba[(y0 * width + x0) * 4 + ch]
      const p01 = rgba[(y0 * width + x1) * 4 + ch]
      const p10 = rgba[(y1 * width + x0) * 4 + ch]
      const p11 = rgba[(y1 * width + x1) * 4 + ch]
      const top = p00 + (p01 - p00) * fx
      const bot = p10 + (p11 - p10) * fx
      out[(y * TARGET + x) * 4 + ch] = Math.round(top + (bot - top) * fy)
    }
  }
}

// --- encode PNG ---
const CRC_TABLE = new Uint32Array(256)
for (let n = 0; n < 256; n++) {
  let c = n
  for (let k = 0; k < 8; k++) {
    c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1
  }
  CRC_TABLE[n] = c >>> 0
}

function crc32(b) {
  let c = 0xffffffff
  for (let i = 0; i < b.length; i++) {
    c = CRC_TABLE[(c ^ b[i]) & 0xff] ^ (c >>> 8)
  }
  return (c ^ 0xffffffff) >>> 0
}

function chunk(type, data) {
  const len = Buffer.alloc(4)
  len.writeUInt32BE(data.length, 0)
  const typeBuf = Buffer.from(type, 'ascii')
  const crcBuf = Buffer.alloc(4)
  crcBuf.writeUInt32BE(crc32(Buffer.concat([typeBuf, data])), 0)
  return Buffer.concat([len, typeBuf, data, crcBuf])
}

const ihdr = Buffer.alloc(13)
ihdr.writeUInt32BE(TARGET, 0)
ihdr.writeUInt32BE(TARGET, 4)
ihdr[8] = 8
ihdr[9] = 6

const scan = Buffer.alloc((TARGET * 4 + 1) * TARGET)
let o = 0
for (let y = 0; y < TARGET; y++) {
  scan[o++] = 0
  out.copy(scan, o, y * TARGET * 4, (y + 1) * TARGET * 4)
  o += TARGET * 4
}

const png = Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  chunk('IHDR', ihdr),
  chunk('IDAT', deflateSync(scan, { level: 9 })),
  chunk('IEND', Buffer.alloc(0))
])

writeFileSync(OUT, png)
console.log(`ported ${width}x${height} -> ${TARGET}x${TARGET}, ${png.length} bytes -> ${OUT}`)
