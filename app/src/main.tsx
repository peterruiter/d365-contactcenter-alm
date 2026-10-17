import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './ui/styles'
import { initTheme, Toaster } from './ui'
import { PowerProvider } from './PowerProvider'
import App from './App'

// Before the first render, so a dark-theme user never sees a flash of the light theme.
initTheme()

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <PowerProvider>
      <Toaster>
        <App />
      </Toaster>
    </PowerProvider>
  </StrictMode>,
)
