import type { Brand } from './types'
import { capgemini } from './capgemini'
import { powerpete } from './powerpete'

export type { Brand }

const brands: Record<string, Brand> = {
  capgemini,
  powerpete,
}

// VITE_BRAND picks the visual identity at build time (same idea as brands/<id>.json in the
// sibling d365-contactcenter-estimator project, just resolved once per build instead of once
// per output file). Power Pete is the default so a clone with no .env still looks right;
// set VITE_BRAND=capgemini for a Capgemini-branded build.
const requestedId = (import.meta.env.VITE_BRAND || 'powerpete').trim().toLowerCase()

export const brand: Brand = brands[requestedId] ?? powerpete
