import { Chip } from '@mui/material'
import CheckCircleIcon from '@mui/icons-material/CheckCircle'
import CancelIcon from '@mui/icons-material/Cancel'
import WarningAmberIcon from '@mui/icons-material/WarningAmber'

export default function StatusChip({ pass, severity }) {
  if (pass) {
    return (
      <Chip
        icon={<CheckCircleIcon />}
        label="Pass"
        color="success"
        size="small"
        variant="outlined"
      />
    )
  }

  const isError = severity === 'error'
  return (
    <Chip
      icon={isError ? <CancelIcon /> : <WarningAmberIcon />}
      label={isError ? 'Fail' : 'Warning'}
      color={isError ? 'error' : 'warning'}
      size="small"
      variant="outlined"
    />
  )
}
