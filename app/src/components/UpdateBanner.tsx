import { useEffect, useState } from 'react'
import { Link, Notice } from '../ui'
import { BUILD, dismiss, isDismissed, isNewer, type UpdateInfo } from '../buildInfo'
import { getUpdate } from '../services/localSetup'

/**
 * Local runner only: says when GitHub has a newer release than the one running. The runner asks
 * GitHub (not the browser), at most every few hours; no answer simply means no banner.
 */
export function UpdateBanner() {
  const [info, setInfo] = useState<UpdateInfo | null>(null)
  const [hidden, setHidden] = useState(false)

  useEffect(() => {
    getUpdate()
      .then(setInfo)
      .catch(() => setInfo(null))
  }, [])

  const latest = info?.latest
  if (!latest || !isNewer(latest) || hidden || isDismissed(latest.build)) return null

  return (
    <Notice
      className="update-banner"
      tone="info"
      title={`A newer version is available: build ${latest.build}`}
      onDismiss={() => {
        dismiss(latest.build)
        setHidden(true)
      }}
      dismissLabel="Not now"
      actions={
        <Link href={info.releaseUrl} target="_blank" rel="noreferrer">
          Download it from GitHub
        </Link>
      }
    >
      You are running build {BUILD.build} ({BUILD.commit}). Build {latest.build} ({latest.commit}) was released{' '}
      {new Date(latest.builtAt).toLocaleDateString()}. Download the new exe or zip, close this one and start the new one: your
      profiles, environments and secrets stay where they are.
    </Notice>
  )
}
