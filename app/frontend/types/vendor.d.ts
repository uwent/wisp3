// Packages without their own types

// shpjs (lib/outlines/read.ts): a zipped shapefile's layers as GeoJSON, reprojected with its .prj
declare module 'shpjs' {
  export function parseZip(buffer: ArrayBuffer | Uint8Array, whiteList?: string[]): Promise<unknown>
}
