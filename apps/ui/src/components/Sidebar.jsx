import {
  Box, Drawer, Typography, List, ListItemButton,
  ListItemIcon, ListItemText, Divider, Chip, Tooltip,
} from '@mui/material'
import AutoAwesomeIcon from '@mui/icons-material/AutoAwesome'
import CloudUploadIcon from '@mui/icons-material/CloudUpload'
import SearchIcon from '@mui/icons-material/ManageSearch'
import GavelIcon from '@mui/icons-material/Gavel'
import ArticleIcon from '@mui/icons-material/Article'

const SIDEBAR_WIDTH = 240

// Agent pipeline items shown at the bottom of the sidebar
const AGENTS = [
  { label: 'Researcher', key: 'researcher', icon: <SearchIcon  fontSize="small" /> },
  { label: 'Auditor',    key: 'auditor',    icon: <GavelIcon   fontSize="small" /> },
  { label: 'Briefer',    key: 'briefer',    icon: <ArticleIcon fontSize="small" /> },
]

/** Returns dot colour + glow for a single agent status string. */
function agentDotStyle(agentStatus) {
  if (agentStatus === 'running') return { color: '#F59E0B', glow: true }
  if (agentStatus === 'done')    return { color: '#16A34A', glow: false }
  if (agentStatus === 'error')   return { color: '#EF4444', glow: false }
  return { color: 'rgba(255,255,255,0.25)', glow: false }
}

/** Derive a single pipeline-level label from the per-agent status map. */
function pipelineLabel(agentStatuses) {
  const vals = Object.values(agentStatuses)
  if (vals.some(v => v === 'error'))   return { label: 'Error',    color: '#EF4444' }
  if (vals.some(v => v === 'running')) return { label: 'Running',  color: '#F59E0B' }
  if (vals.every(v => v === 'done'))   return { label: 'Complete', color: '#16A34A' }
  return { label: 'Standby', color: 'rgba(255,255,255,0.25)' }
}

const NAV = [
  { label: 'Validate Asset', icon: <CloudUploadIcon fontSize="small" /> },
]

const sidebarStyles = {
  width: SIDEBAR_WIDTH,
  flexShrink: 0,
  '& .MuiDrawer-paper': {
    width: SIDEBAR_WIDTH,
    boxSizing: 'border-box',
    bgcolor: '#0f2027',
    borderRight: 'none',
    display: 'flex',
    flexDirection: 'column',
  },
}

export { SIDEBAR_WIDTH }

export default function Sidebar({ activePage = 'Validate Asset', agentStatuses = {} }) {
  const statuses = { researcher: 'idle', auditor: 'idle', briefer: 'idle', ...agentStatuses }
  const { label: statusLabel, color: statusColor } = pipelineLabel(statuses)

  return (
    <Drawer variant="permanent" sx={sidebarStyles}>
      {/* Brand header */}
      <Box sx={{ px: 2.5, py: 2.5, display: 'flex', alignItems: 'center', gap: 1.5 }}>
        <Box sx={{
          width: 34, height: 34,
          bgcolor: 'primary.main',
          borderRadius: 2,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          flexShrink: 0,
        }}>
          <AutoAwesomeIcon sx={{ fontSize: 18, color: '#fff' }} />
        </Box>
        <Box>
          <Typography variant="subtitle1" sx={{ color: '#fff', lineHeight: 1.2, letterSpacing: '-0.01em' }}>
            BrandSense
          </Typography>
          <Typography variant="caption" sx={{ color: 'rgba(255,255,255,0.45)', fontSize: '0.68rem' }}>
            AI Asset Validation
          </Typography>
        </Box>
      </Box>

      <Divider sx={{ borderColor: 'rgba(255,255,255,0.08)' }} />

      {/* Navigation */}
      <Box sx={{ px: 1.5, pt: 2 }}>
        <Typography variant="caption" sx={{
          color: 'rgba(255,255,255,0.35)',
          fontWeight: 600,
          letterSpacing: '0.08em',
          textTransform: 'uppercase',
          fontSize: '0.65rem',
          px: 1,
        }}>
          Workspace
        </Typography>
        <List disablePadding sx={{ mt: 0.5 }}>
          {NAV.map((item) => {
            const active = item.label === activePage
            return (
              <ListItemButton
                key={item.label}
                selected={active}
                sx={{
                  borderRadius: 1.5,
                  mb: 0.5,
                  pl: 1.5,
                  color: active ? '#fff' : 'rgba(255,255,255,0.7)',
                  borderLeft: active ? '3px solid' : '3px solid transparent',
                  borderColor: active ? 'primary.main' : 'transparent',
                  bgcolor: active ? 'rgba(0,120,212,0.2)' : 'transparent',
                  '&:hover': { bgcolor: 'rgba(255,255,255,0.06)' },
                  '&.Mui-selected': {
                    bgcolor: 'rgba(0,120,212,0.2)',
                    '&:hover': { bgcolor: 'rgba(0,120,212,0.28)' },
                  },
                }}
              >
                <ListItemIcon sx={{ minWidth: 32, color: 'inherit' }}>
                  {item.icon}
                </ListItemIcon>
                <ListItemText
                  primary={item.label}
                  primaryTypographyProps={{ variant: 'body2', fontWeight: active ? 600 : 400 }}
                />
              </ListItemButton>
            )
          })}
        </List>
      </Box>

      {/* Spacer */}
      <Box sx={{ flexGrow: 1 }} />

      <Divider sx={{ borderColor: 'rgba(255,255,255,0.08)', mx: 1.5 }} />

      {/* AI Pipeline status */}
      <Box sx={{ px: 2.5, py: 2 }}>
        <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', mb: 1.5 }}>
          <Typography variant="caption" sx={{
            color: 'rgba(255,255,255,0.35)',
            fontWeight: 600,
            letterSpacing: '0.08em',
            textTransform: 'uppercase',
            fontSize: '0.65rem',
          }}>
            AI Pipeline
          </Typography>
          <Chip
            label={statusLabel}
            size="small"
            sx={{
              height: 18,
              fontSize: '0.6rem',
              fontWeight: 600,
              bgcolor: `${statusColor}22`,
              color: statusColor,
              border: `1px solid ${statusColor}55`,
              '& .MuiChip-label': { px: 1 },
            }}
          />
        </Box>

        {AGENTS.map((agent) => {
          const { color: dotColor, glow } = agentDotStyle(statuses[agent.key])
          const dotLabel = statuses[agent.key] === 'running' ? 'Running'
                         : statuses[agent.key] === 'done'    ? 'Complete'
                         : statuses[agent.key] === 'error'   ? 'Error'
                         : 'Standby'
          return (
            <Box key={agent.label}
              sx={{ display: 'flex', alignItems: 'center', gap: 1.5, mb: 1.25 }}>
              <Box sx={{
                width: 28, height: 28,
                borderRadius: '50%',
                bgcolor: 'rgba(255,255,255,0.07)',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                color: 'rgba(255,255,255,0.5)',
                flexShrink: 0,
              }}>
                {agent.icon}
              </Box>
              <Box sx={{ flexGrow: 1 }}>
                <Typography variant="caption" sx={{ color: 'rgba(255,255,255,0.7)', display: 'block', lineHeight: 1.3 }}>
                  {agent.label}
                </Typography>
              </Box>
              <Tooltip title={dotLabel}>
                <Box sx={{
                  width: 7, height: 7,
                  borderRadius: '50%',
                  bgcolor: dotColor,
                  flexShrink: 0,
                  boxShadow: glow ? `0 0 6px ${dotColor}` : 'none',
                }} />
              </Tooltip>
            </Box>
          )
        })}
      </Box>

      {/* Footer */}
      <Box sx={{ px: 2.5, pb: 2 }}>
        <Typography variant="caption" sx={{ color: 'rgba(255,255,255,0.2)', fontSize: '0.62rem' }}>
          Azure AI Foundry · v1.0
        </Typography>
      </Box>
    </Drawer>
  )
}
