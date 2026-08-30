import { useEffect, useState, type CSSProperties } from 'react'
import { FluentProvider, Switch } from '@fluentui/react-components'
import { lightTheme, darkTheme } from './theme'
import { ComparePage } from './pages/ComparePage'
import { Footer } from './components/Footer'
import { brand } from './brands'
import './styles/app.css'

export default function App() {
  const [dark, setDark] = useState<boolean>(false)

  // Browser tab title and favicon follow the active brand too - both are set once here rather
  // than duplicated as static values in index.html, so src/brands/ stays the single source of
  // truth for a brand's identity.
  useEffect(() => {
    document.title = brand.productTitle
    const link = document.querySelector<HTMLLinkElement>("link[rel~='icon']")
    if (link) {
      link.href = brand.favicon
      link.type = brand.favicon.endsWith('.png') ? 'image/png' : 'image/svg+xml'
    }
  }, [])

  const brandVars = {
    '--brand-primary': brand.colors.primary,
    '--brand-primary-dark': brand.colors.primaryDark,
    '--brand-accent': brand.colors.accent,
  } as CSSProperties

  return (
    <FluentProvider theme={dark ? darkTheme : lightTheme} style={{ height: '100%' }}>
      <div className={`app-shell${dark ? ' theme-dark' : ''}`} style={brandVars}>
        <header className="app-header">
          <div className="brand">
            {/* Always the light/white logo variant: the header background is always the brand's
                colored gradient, light-on-dark, regardless of the light/dark theme toggle below. */}
            <img className="brand-logo" src={brand.logoLight} alt={brand.logoAlt} />
          </div>
          <div className="header-divider" />
          <div className="header-title">
            <span className="header-product">{brand.productTitle}</span>
            <span className="header-sub">{brand.headerSubtitle}</span>
          </div>
          <div className="header-actions">
            {/* The header background is always the brand's colored gradient, regardless of the
                light/dark toggle below, but Fluent colors this switch from the active theme - in
                light mode that means a dark thumb/icon that disappears against it. Nesting a dark-themed
                provider here (rather than guessing at Fluent's internal class names) makes Fluent
                render the switch with its own correct light-on-dark contrast unconditionally. */}
            <FluentProvider theme={darkTheme} style={{ background: 'transparent' }}>
              <Switch checked={dark} onChange={(_, d) => setDark(d.checked)} label={dark ? 'Dark' : 'Light'} />
            </FluentProvider>
          </div>
        </header>

        <main className="app-body">
          <div className="content">
            <ComparePage />
          </div>
          <Footer />
        </main>
      </div>
    </FluentProvider>
  )
}
