import { useState } from 'react'
import {
  Box, AppBar, Toolbar, Typography, Grid, Divider,
  IconButton, Avatar, Tooltip, Paper, Chip,
} from '@mui/material'
import NotificationsNoneIcon from '@mui/icons-material/NotificationsNone'
import HelpOutlineIcon from '@mui/icons-material/HelpOutline'
import CloudUploadIcon from '@mui/icons-material/CloudUpload'
import AutoAwesomeIcon from '@mui/icons-material/AutoAwesome'
import CheckCircleOutlineIcon from '@mui/icons-material/CheckCircleOutline'
import ArrowForwardIcon from '@mui/icons-material/ArrowForward'
import Sidebar from './components/Sidebar'
import UploadPanel from './components/UploadPanel'
import ResultsPanel from './components/ResultsPanel'
import { validateAssetStream } from './api/client'

const STEPS = [
  {
    number: '01',
    icon: <CloudUploadIcon sx={{ fontSize: 24, color: 'primary.main' }} />,
    title: 'Upload Asset',
    desc: 'Upload a PDF marketing asset up to 50 MB.',
  },
  {
    number: '02',
    icon: <AutoAwesomeIcon sx={{ fontSize: 24, color: 'primary.main' }} />,
    title: 'AI Analysis',
    desc: 'Researcher, Auditor, and Briefer agents check brand, legal, and SEO compliance.',
  },
  {
    number: '03',
    icon: <CheckCircleOutlineIcon sx={{ fontSize: 24, color: 'primary.main' }} />,
    title: 'Review Results',
    desc: 'Receive a scored report with pass/fail checks and a creative brief.',
  },
]

export default function App() {
  const [status, setStatus] = useState('idle') // idle | loading | success | error
  const [result, setResult] = useState(null)
  const [errorMsg, setErrorMsg] = useState('')
  const [agentStatuses, setAgentStatuses] = useState({ researcher: 'idle', auditor: 'idle', briefer: 'idle' })
  const [progressMsg, setProgressMsg] = useState('')

  async function handleValidate(file) {
    setStatus('loading')
    setResult(null)
    setErrorMsg('')
    setProgressMsg('')
    setAgentStatuses({ researcher: 'idle', auditor: 'idle', briefer: 'idle' })
    try {
      for await (const event of validateAssetStream(file)) {
        if (event.event === 'progress') {
          setAgentStatuses(prev => ({ ...prev, [event.agent]: event.status }))
          setProgressMsg(event.message)
        } else if (event.event === 'complete') {
          setResult(event.result)
          setStatus('success')
        } else if (event.event === 'error') {
          setErrorMsg(event.message ?? 'Validation failed. Please try again.')
          setStatus('error')
        }
      }
    } catch (err) {
      setErrorMsg(err.message ?? 'Validation failed. Please try again.')
      setStatus('error')
    }
  }

  function handleReset() {
    setStatus('idle')
    setResult(null)
    setErrorMsg('')
    setProgressMsg('')
    setAgentStatuses({ researcher: 'idle', auditor: 'idle', briefer: 'idle' })
  }

  const hasResults = result !== null || (status === 'error' && errorMsg)

  return (
    <Box sx={{ display: 'flex', minHeight: '100vh', bgcolor: 'background.default' }}>
      {/* Left Sidebar — always visible */}
      <Sidebar agentStatuses={agentStatuses} />

      {/* Main content column */}
      <Box sx={{ flexGrow: 1, display: 'flex', flexDirection: 'column', minWidth: 0 }}>

        {/* Top bar */}
        <AppBar position="static" elevation={0} sx={{
          bgcolor: 'background.paper',
          borderBottom: '1px solid',
          borderColor: 'grey.200',
        }}>
          <Toolbar sx={{ minHeight: '56px !important' }}>
            <Box sx={{ flexGrow: 1 }}>
              <Typography variant="subtitle1" color="text.primary" fontWeight={600}>
                Validate Asset
              </Typography>
              <Typography variant="caption" color="text.secondary">
                AI Marketing Compliance
              </Typography>
            </Box>
            <Tooltip title="Help">
              <IconButton size="small" sx={{ mr: 0.5 }}>
                <HelpOutlineIcon fontSize="small" />
              </IconButton>
            </Tooltip>
            <Tooltip title="Notifications">
              <IconButton size="small" sx={{ mr: 1.5 }}>
                <NotificationsNoneIcon fontSize="small" />
              </IconButton>
            </Tooltip>
            <Divider orientation="vertical" flexItem sx={{ mr: 1.5, my: 1 }} />
            <Tooltip title="User account">
              <Avatar sx={{ width: 30, height: 30, bgcolor: 'primary.main', fontSize: '0.75rem', cursor: 'pointer' }}>
                BS
              </Avatar>
            </Tooltip>
          </Toolbar>
        </AppBar>

        {/* Scrollable page content */}
        <Box sx={{ flexGrow: 1, overflow: 'auto', p: { xs: 2, md: 3 } }}>

          {/* ── Hero — always visible ── */}
          <Box sx={{ mb: 3 }}>
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 0.5 }}>
              <Chip label="AI-Powered" size="small" sx={{
                bgcolor: 'primary.main', color: '#fff',
                fontWeight: 600, fontSize: '0.68rem', height: 22,
              }} />
            </Box>
            <Typography variant="h5" fontWeight={700} sx={{ mt: 1 }}>
              Validate Your Marketing Asset
            </Typography>
            <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5, maxWidth: 620 }}>
              Ensure brand consistency, legal compliance, and SEO readiness before publishing — powered by Azure AI Foundry agents.
            </Typography>
          </Box>

          {/* ── Step cards — always visible, compact ── */}
          <Grid container spacing={2} sx={{ mb: 3 }}>
            {STEPS.map((step, i) => (
              <Grid item xs={12} sm={4} key={step.number}>
                <Paper elevation={0} sx={{
                  p: 2,
                  height: '100%',
                  border: '1px solid',
                  borderColor: 'grey.200',
                  borderRadius: 2,
                  position: 'relative',
                  overflow: 'hidden',
                  '&::before': {
                    content: '""',
                    position: 'absolute',
                    top: 0, left: 0, right: 0,
                    height: 3,
                    bgcolor: 'primary.main',
                    opacity: 0.7,
                  },
                }}>
                  <Box sx={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', mb: 1 }}>
                    {step.icon}
                    <Typography sx={{ color: 'grey.200', fontWeight: 800, fontSize: '1.4rem', lineHeight: 1 }}>
                      {step.number}
                    </Typography>
                  </Box>
                  <Typography variant="subtitle2" gutterBottom>{step.title}</Typography>
                  <Typography variant="body2" color="text.secondary" sx={{ lineHeight: 1.5, fontSize: '0.8rem' }}>
                    {step.desc}
                  </Typography>
                  {i < STEPS.length - 1 && (
                    <ArrowForwardIcon sx={{
                      display: { xs: 'none', sm: 'block' },
                      position: 'absolute', right: -14, top: '50%',
                      transform: 'translateY(-50%)',
                      color: 'grey.300', fontSize: 18, zIndex: 1,
                    }} />
                  )}
                </Paper>
              </Grid>
            ))}
          </Grid>

          {/* ── Upload + Results row ── */}
          <Grid container spacing={3} alignItems="flex-start">
            {/* Upload panel — fixed left column */}
            <Grid item xs={12} md={4} lg={3}>
              <UploadPanel
                status={status}
                onValidate={handleValidate}
                onReset={handleReset}
                errorMsg={errorMsg}
                agentStatuses={agentStatuses}
                progressMsg={progressMsg}
              />
            </Grid>

            {/* Results — appears in right column once available */}
            {hasResults && (
              <Grid item xs={12} md={8} lg={9}>
                <ResultsPanel result={result} />
              </Grid>
            )}
          </Grid>

        </Box>
      </Box>
    </Box>
  )
}
