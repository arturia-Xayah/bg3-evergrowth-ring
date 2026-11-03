// Optional artwork export only. Normal tools/build.py uses committed DDS assets.
// Install with: npm install --prefix tools/icon-deps
// Then: node tools/build_icons.cjs
const fs = require('node:fs');
const path = require('node:path');
const {createRequire} = require('node:module');
const optionalRequire = createRequire(path.join(__dirname, 'icon-deps', 'package.json'));
const sharp = optionalRequire('sharp');
const dxt = optionalRequire('dxt-js');
const root = path.resolve(__dirname, '..');
const name = 'ER_Item_EvergrowthRing';
const original = path.join(root, 'artwork', 'evergrowth-ring-icon.png');

function write(file, data) {
    fs.mkdirSync(path.dirname(file), {recursive: true});
    fs.writeFileSync(file, data);
}

function dds(rgba, size) {
    const flags = dxt.flags.DXT5 | dxt.flags.ColourClusterFit | dxt.flags.WeightColourByAlpha;
    const blocks = Buffer.from(dxt.compress(rgba, size, size, flags));
    if (blocks.length !== Math.ceil(size / 4) ** 2 * 16) throw new Error('Invalid BC3 size');
    const header = Buffer.alloc(128);
    header.write('DDS ', 0, 'ascii');
    header.writeUInt32LE(124, 4);
    header.writeUInt32LE(0x81007, 8); // caps, height, width, pixel format, linear size
    header.writeUInt32LE(size, 12);
    header.writeUInt32LE(size, 16);
    header.writeUInt32LE(blocks.length, 20);
    header.writeUInt32LE(1, 28); // exactly one level, no mip chain
    header.writeUInt32LE(32, 76);
    header.writeUInt32LE(4, 80); // DDPF_FOURCC
    header.write('DXT5', 84, 'ascii');
    header.writeUInt32LE(0x1000, 108); // DDSCAPS_TEXTURE
    const decoded = Buffer.from(dxt.decompress(blocks, size, size, dxt.flags.DXT5));
    const center = (Math.floor(size / 2) * size + Math.floor(size / 2)) * 4 + 3;
    if (decoded[3] > 8 || decoded[center] > 8) throw new Error('Lost transparent border or ring hole');
    return {file: Buffer.concat([header, blocks]), decoded};
}

async function main() {
    for (const size of [64, 144, 380]) {
        // Technical resizing/encoding only; the ring itself is imagegen artwork.
        const image = sharp(original).resize(size, size, {fit: 'contain'}).ensureAlpha().toColourspace('srgb');
        const rgba = await image.clone().raw().toBuffer();
        const png = await image.clone().png().toBuffer();
        write(path.join(root, 'artwork', 'icons', String(size), name + '.png'), png);
        const converted = dds(rgba, size);
        write(path.join(root, 'artwork', 'icons', String(size), name + '-bc3-preview.png'),
            await sharp(converted.decoded, {raw: {width: size, height: size, channels: 4}}).png().toBuffer());
        if (size === 64) {
            write(path.join(root, 'source/Public/EvergrowthRing/Assets/Textures/Icons/ER_Icons_Evergrowth.dds'), converted.file);
        } else {
            const folder = size === 144 ? 'ControllerUIIcons/items_png' : 'Tooltips/ItemIcons';
            for (const assets of ['Assets', 'AssetsLowRes']) {
                // Full-size low-res fallback copies deliberately preserve metadata
                // dimensions; these are compatibility copies, not memory savings.
                write(path.join(root, 'source/Mods/EvergrowthRing/GUI', assets, folder, name + '.DDS'), converted.file);
            }
        }
    }
    console.log('Exported alpha-preserving 64/144/380 PNG and BC3 DDS icons. Game rendering remains untested.');
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
