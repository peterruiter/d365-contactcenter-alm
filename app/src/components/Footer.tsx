import { Text } from '@fluentui/react-components'
import { brand } from '../brands'

export function Footer() {
  const { footer } = brand
  return (
    <footer className="app-footer">
      <div className="footer-line">
        <img className="footer-icon" src={footer.icon} alt="" />
        <a href={footer.taglineHref} target="_blank" rel="noopener noreferrer">
          {footer.tagline}
        </a>
      </div>
      <Text size={200} block className="footer-disclaimer">
        {footer.disclaimer}
      </Text>
      <Text size={200} block className="footer-creator">
        {footer.creator.before} <b>{footer.creator.name}</b>
        {footer.creator.after} · <a href={footer.creator.mailHref}>Mail</a> ·{' '}
        <a href={footer.creator.teamsHref} target="_blank" rel="noopener noreferrer">
          Chat on Teams
        </a>{' '}
        ·{' '}
        <a href={footer.creator.extraHref} target="_blank" rel="noopener noreferrer">
          {footer.creator.extraLabel}
        </a>
      </Text>
    </footer>
  )
}
