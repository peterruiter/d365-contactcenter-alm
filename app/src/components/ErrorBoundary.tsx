import { Component, type ErrorInfo, type ReactNode } from 'react'
import { Button, Notice } from '../ui'
import { buildLabel } from '../buildInfo'

interface State {
  error: Error | null
}

/**
 * A page that throws while drawing shows what went wrong and a way back, instead of the blank
 * page React leaves behind. Nothing is lost by starting over: runs carry on in the backend.
 */
export class ErrorBoundary extends Component<{ children: ReactNode }, State> {
  state: State = { error: null }

  static getDerivedStateFromError(error: Error): State {
    return { error }
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error('Contact Center ALM: a page failed to draw.', error, info.componentStack)
  }

  render() {
    const { error } = this.state
    if (!error) return this.props.children
    return (
      <Notice
        tone="error"
        title="This page could not be shown"
        actions={
          <Button size="sm" onClick={() => window.location.reload()}>
            Start again
          </Button>
        }
      >
        Something in the data could not be displayed. Runs in progress carry on in the background and show up again when you
        come back. If this keeps happening, send this to the maintainer: <code>{error.message}</code> ({buildLabel()}).
      </Notice>
    )
  }
}
