import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { PowerProvider } from './PowerProvider'
import App from './App'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <PowerProvider>
      <App />
    </PowerProvider>
  </StrictMode>,
)
