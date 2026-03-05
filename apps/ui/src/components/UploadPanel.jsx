import { useState, useCallback } from 'react'
import {
  Paper, Typography, Button, Box, Alert,
  CircularProgress, Divider, IconButton, Tooltip,
} from '@mui/material'
import UploadFileIcon from '@mui/icons-material/UploadFile'
import CheckCircleOutlineIcon from '@mui/icons-material/CheckCircleOutline'
import CheckCircleIcon from '@mui/icons-material/CheckCircle'
import ErrorOutlineIcon from '@mui/icons-material/ErrorOutline'
import RestartAltIcon from '@mui/icons-material/RestartAlt'
import SearchIcon from '@mui/icons-material/ManageSearch'
import GavelIcon from '@mui/icons-material/Gavel'
import ArticleIcon from '@mui/icons-material/Article'

const ACCEPTED = 'application/pdf'
const MAX_MB = 50

const AGENT_STEPS = [
  { key: 'researcher', label: 'Researcher', icon: SearchIcon,  desc: 'Retrieving guidelines' },
  { key: 'auditor',    label: 'Auditor',    icon: GavelIcon,   desc: 'Auditing asset' },
  { key: 'briefer',    label: 'Briefer',    icon: ArticleIcon, desc: 'Generating brief' },
]

function AgentStepper({ agentStatuses, progressMsg }) {
  return (
    <Box sx={{ width: '100%' }}>
      {AGENT_STEPS.map((step, i) => {
        const s = agentStatuses?.[step.key] ?? 'idle'
        const Icon = step.icon
        const isRunning = s === 'running'
        const isDone    = s === 'done'
        const isError   = s === 'error'
        const dotColor  = isRunning ? '#F59E0B' : isDone ? '#16A34A' : isError ? '#EF4444' : 'text.disabled'
        return (
          <Box key={step.key} sx={{ display: 'flex', alignItems: 'center', gap: 1.5, mb: i < 2 ? 1.5 : 0 }}>
            {/* Step icon */}
            <Box sx={{
              width: 32, height: 32, borderRadius: '50%', flexShrink: 0,
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              bgcolor: isDone ? 'success.50' : isRunning ? 'warning.50' : isError ? 'error.50' : 'grey.100',
            }}>
              {isRunning
                ? <CircularProgress size={16} thickness={5} sx={{ color: '#F59E0B' }} />
                : isDone
                  ? <CheckCircleIcon sx={{ fontSize: 16, color: 'success.main' }} />
                  : isError
                    ? <ErrorOutlineIcon sx={{ fontSize: 16, color: 'error.main' }} />
                    : <Icon sx={{ fontSize: 16, color: 'text.disabled' }} />
              }
            </Box>
            {/* Label + live message */}
            <Box sx={{ flexGrow: 1, minWidth: 0 }}>
              <Typography variant="caption" fontWeight={600}
                sx={{ color: isRunning ? 'warning.dark' : isDone ? 'success.dark' : isError ? 'error.main' : 'text.disabled', display: 'block' }}>
                {step.label}
              </Typography>
              <Typography variant="caption" color="text.disabled" noWrap display="block" sx={{ fontSize: '0.68rem' }}>
                {isRunning && progressMsg ? progressMsg : step.desc}
              </Typography>
            </Box>
            {/* Status dot */}
            <Box sx={{
              width: 7, height: 7, borderRadius: '50%', flexShrink: 0,
              bgcolor: dotColor,
              boxShadow: isRunning ? `0 0 6px ${dotColor}` : 'none',
            }} />
          </Box>
        )
      })}
    </Box>
  )
}

export default function UploadPanel({ status, onValidate, onReset, errorMsg, agentStatuses, progressMsg }) {
  const [file, setFile] = useState(null)
  const [dragOver, setDragOver] = useState(false)

  const isLoading = status === 'loading'
  const isDone = status === 'success' || status === 'error'

  function selectFile(f) {
    if (!f) return
    if (f.type !== ACCEPTED) {
      alert('Only PDF files are accepted.')
      return
    }
    if (f.size > MAX_MB * 1024 * 1024) {
      alert(`File must be under ${MAX_MB} MB.`)
      return
    }
    setFile(f)
  }

  const onDrop = useCallback((e) => {
    e.preventDefault()
    setDragOver(false)
    selectFile(e.dataTransfer.files[0])
  }, [])

  function handleReset() {
    setFile(null)
    onReset()
  }

  return (
    <Paper elevation={2} sx={{ p: 3, height: '100%' }}>
      <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', mb: 2 }}>
        <Typography variant="h6">Upload Asset</Typography>
        {isDone && (
          <Tooltip title="Start over">
            <IconButton size="small" onClick={handleReset}>
              <RestartAltIcon fontSize="small" />
            </IconButton>
          </Tooltip>
        )}
      </Box>

      {/* Drop zone */}
      <Box
        onDragOver={(e) => { e.preventDefault(); setDragOver(true) }}
        onDragLeave={() => setDragOver(false)}
        onDrop={onDrop}
        onClick={() => !isLoading && !isDone && document.getElementById('file-input').click()}
        sx={{
          border: '2px dashed',
          borderColor: dragOver ? 'primary.main' : 'grey.300',
          borderRadius: 2,
          p: 4,
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          gap: 1,
          bgcolor: dragOver ? 'primary.50' : 'grey.50',
          cursor: isLoading || isDone ? 'default' : 'pointer',
          transition: 'all 0.2s ease',
          '&:hover': !isLoading && !isDone ? { borderColor: 'primary.main', bgcolor: 'grey.100' } : {},
        }}
      >
        {isLoading ? (
          <Box sx={{ width: '100%' }}>
            <AgentStepper agentStatuses={agentStatuses} progressMsg={progressMsg} />
          </Box>
        ) : file && isDone ? (
          <CheckCircleOutlineIcon color="success" sx={{ fontSize: 40 }} />
        ) : (
          <UploadFileIcon sx={{ fontSize: 40, color: 'grey.400' }} />
        )}

        {!isLoading && (
          <Typography variant="body2" color="text.secondary" align="center">
            {file ? file.name : 'Drag & drop a PDF here, or click to browse'}
          </Typography>
        )}
        {!file && !isLoading && (
          <Typography variant="caption" color="text.disabled">
            PDF · max {MAX_MB} MB
          </Typography>
        )}
        <input
          id="file-input"
          type="file"
          accept={ACCEPTED}
          hidden
          onChange={(e) => selectFile(e.target.files[0])}
        />
      </Box>

      {/* File info */}
      {file && !isDone && (
        <Box sx={{ mt: 2 }}>
          <Divider sx={{ mb: 1.5 }} />
          <Typography variant="caption" color="text.secondary" display="block" noWrap>
            {file.name} — {(file.size / 1024).toFixed(0)} KB
          </Typography>
          <Button
            variant="contained"
            fullWidth
            sx={{ mt: 1.5 }}
            disabled={isLoading}
            onClick={() => onValidate(file)}
            startIcon={isLoading ? <CircularProgress size={16} color="inherit" /> : null}
          >
            {isLoading ? 'Validating…' : 'Validate Asset'}
          </Button>
        </Box>
      )}

      {/* Error */}
      {status === 'error' && errorMsg && (
        <Alert severity="error" sx={{ mt: 2 }} onClose={handleReset}>
          {errorMsg}
        </Alert>
      )}
    </Paper>
  )
}
