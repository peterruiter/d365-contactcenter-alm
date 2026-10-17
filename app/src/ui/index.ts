// Capgemini (Zodiak) UI layer. Import the styles once at the entry: `import './ui/styles'`.
// Components paint with semantic tokens only and follow `data-theme` on <html>.

export { cx, type Tone } from './utils'

// Design-system components
export { Button, type ButtonProps } from './Button'
export { IconButton, type IconButtonProps } from './IconButton'
export { Link, type LinkProps } from './Link'
export { Tag, type TagProps } from './Tag'
export { Card, type CardProps } from './Card'
export { Input, type InputProps } from './Input'
export { Textarea, type TextareaProps } from './Textarea'
export { Select, type SelectProps, type SelectOption } from './Select'
export { Checkbox, type CheckboxProps } from './Checkbox'
export { Accordion, type AccordionProps, type AccordionItem } from './Accordion'
export {
  Disclosure,
  DisclosureChevron,
  type DisclosureProps,
  type DisclosureRenderArgs,
  type DisclosureTriggerProps,
} from './Disclosure'
export { Table, THead, TBody, Tr, Th, Td, type TableProps, type TrProps, type ThProps, type TdProps } from './Table'

// App primitives
export { AppHeader, type AppHeaderProps } from './AppHeader'
export { AppFooter, type AppFooterProps } from './AppFooter'
export { CapgeminiLogo, CAPGEMINI_LOGOS, type CapgeminiLogoProps } from './CapgeminiLogo'
export { Tabs, TabPanel, type TabsProps, type TabItem, type TabPanelProps } from './Tabs'
export { Stepper, type StepperProps, type StepItem, type StepState } from './Stepper'
export { Switch, type SwitchProps } from './Switch'
export { ThemeToggle, useTheme, initTheme, setTheme, type Theme, type ThemeToggleProps } from './ThemeToggle'
export { Panel, type PanelProps } from './Panel'
export { Notice, type NoticeProps, type NoticeTone } from './Notice'
export {
  StatusDot,
  StatusLabel,
  STATUS_STYLES,
  STATUS_KINDS,
  type StatusKind,
  type StatusShape,
  type StatusStyle,
  type StatusDotProps,
  type StatusLabelProps,
} from './StatusDot'
export { Badge, type BadgeProps } from './Badge'
export { Spinner, type SpinnerProps } from './Spinner'
export { ProgressBar, type ProgressBarProps } from './ProgressBar'
export { Dialog, type DialogProps } from './Dialog'
export { Toaster, useToast, type ToastOptions, type ToastApi, type ToasterProps } from './Toaster'
export { EmptyState, type EmptyStateProps } from './EmptyState'
export { Skeleton, SkeletonText, type SkeletonProps, type SkeletonTextProps } from './Skeleton'
export { Tooltip, type TooltipProps } from './Tooltip'
export { SearchInput, type SearchInputProps } from './SearchInput'
export { FilterChips, type FilterChipsProps, type FilterChip } from './FilterChips'
export { KeyValue, type KeyValueProps, type KeyValueItem } from './KeyValue'
