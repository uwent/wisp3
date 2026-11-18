import { router } from '@inertiajs/svelte'

// Google Analytics on the public pages only (PLAN.md H.1). The layout names the measurement ID in a
// meta tag when GA_MEASUREMENT_ID is set (production); without it nothing here runs. gtag.js loads
// the first time a tracked page is shown, so a grower who arrives signed in never loads it. Signed
// in, or on any page not listed, GA's own opt-out flag is set, so nothing is sent. Page views are
// sent by WISP (Inertia's navigations aren't page loads), with every query parameter but utm_*
// removed from the page and referrer addresses, so a token in an emailed link can't reach Google.

/** The signed-out pages tracked; pages reached with a token (sign-in link, password reset, confirmation, unsubscribe) aren't */
export const TRACKED_PAGES = new Set(['Pages/Home', 'Pages/About', 'Auth/SignIn', 'Auth/SignUp', 'Auth/ForgotPassword'])

type PageInfo = { component: string; props: { auth?: { user?: unknown }; example?: unknown } }

/** Whether GA may see the page: signed out, and a listed page or the example farm (its data is public) */
export function tracked(page: PageInfo): boolean {
  if (page.props.auth?.user) return false
  return TRACKED_PAGES.has(page.component) || Boolean(page.props.example)
}

/** An address without its fragment or any query parameter except utm_*; '' for one that isn't a URL */
export function cleanUrl(href: string, base?: string): string {
  let url: URL
  try {
    url = new URL(href, base)
  } catch {
    return ''
  }
  const kept = new URLSearchParams()
  url.searchParams.forEach((value, key) => {
    if (key.startsWith('utm_')) kept.append(key, value)
  })
  const query = kept.toString()
  return `${url.origin}${url.pathname}${query ? `?${query}` : ''}`
}

type Gtag = (...args: unknown[]) => void
type AnalyticsWindow = { dataLayer?: unknown[]; gtag?: Gtag } & Record<string, unknown>

/** The window with gtag's globals and GA's opt-out flags */
const win = () => window as unknown as AnalyticsWindow

let id: string | null = null
let loaded = false
let lastLocation: string | null = null
let referrer = ''

function load(measurementId: string) {
  const w = win()
  w.dataLayer = w.dataLayer || []
  w.gtag = function gtag() {
    // gtag.js reads the arguments object itself, as its snippet does
    // eslint-disable-next-line prefer-rest-params
    w.dataLayer!.push(arguments)
  }
  w.gtag('js', new Date())
  w.gtag('set', { page_location: cleanUrl(window.location.href), page_referrer: referrer })
  w.gtag('config', measurementId, { send_page_view: false })
  const script = document.createElement('script')
  script.async = true
  script.src = `https://www.googletagmanager.com/gtag/js?id=${encodeURIComponent(measurementId)}`
  document.head.appendChild(script)
  loaded = true
}

function pageShown(page: PageInfo) {
  if (!id) return
  const allowed = tracked(page)
  // GA's opt-out flag: while it's set, gtag sends nothing at all
  win()[`ga-disable-${id}`] = !allowed
  if (!allowed) return

  const location = cleanUrl(window.location.href)
  if (location === lastLocation) return
  if (!loaded) load(id)
  const w = win()
  const addresses = { page_location: location, page_referrer: lastLocation ?? referrer }
  w.gtag?.('set', addresses)
  // After the page's <svelte:head> has set its title
  requestAnimationFrame(() => w.gtag?.('event', 'page_view', { ...addresses, page_title: document.title }))
  lastLocation = location
  if (page.props.example) exampleOpened()
}

// Once a browser session: the first page of the example farm
function exampleOpened() {
  try {
    if (sessionStorage.getItem('wisp-example-opened')) return
    sessionStorage.setItem('wisp-example-opened', '1')
  } catch {
    // Storage blocked: counted on each page of the example instead of once
  }
  track('example_open')
}

/** An event (sign_up, example_open), sent only from a tracked page */
export function track(name: string) {
  if (!id || !loaded) return
  if (win()[`ga-disable-${id}`]) return
  win().gtag?.('event', name)
}

/** Watches Inertia's page changes (the first included) when the layout names a measurement ID */
export function startAnalytics() {
  id = document.querySelector<HTMLMetaElement>('meta[name="ga-measurement-id"]')?.content || null
  if (!id) return
  referrer = document.referrer ? cleanUrl(document.referrer) : ''
  router.on('navigate', (event) => pageShown(event.detail.page as PageInfo))
}
