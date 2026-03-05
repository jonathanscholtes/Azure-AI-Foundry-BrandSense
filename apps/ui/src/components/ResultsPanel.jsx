import {
  Box, Paper, Typography, Grid, Divider, Chip, List, ListItem, ListItemIcon, ListItemText,
} from '@mui/material'
import CheckCircleIcon from '@mui/icons-material/CheckCircle'
import CancelIcon from '@mui/icons-material/Cancel'
import WarningAmberIcon from '@mui/icons-material/WarningAmber'
import ArrowRightIcon from '@mui/icons-material/ArrowRight'

/** 0-10 → letter grade + colour */
function gradeFromScore(score) {
  if (score >= 9) return { letter: 'A', color: '#16A34A' }
  if (score >= 7) return { letter: 'B', color: '#65A30D' }
  if (score >= 5) return { letter: 'C', color: '#D97706' }
  if (score >= 3) return { letter: 'D', color: '#EA580C' }
  return { letter: 'F', color: '#DC2626' }
}

// --- Score badge ----------------------------------------------------------
function ScoreBadge({ score }) {
  const { letter, color } = gradeFromScore(score)
  return (
    <Box sx={{
      width: 72, height: 72, borderRadius: '50%', flexShrink: 0,
      border: `4px solid ${color}`,
      display: 'flex', flexDirection: 'column',
      alignItems: 'center', justifyContent: 'center',
    }}>
      <Typography sx={{ fontWeight: 800, fontSize: '1.6rem', lineHeight: 1, color }}>
        {letter}
      </Typography>
      <Typography sx={{ fontSize: '0.65rem', color: 'text.secondary', lineHeight: 1.2 }}>
        {score}/10
      </Typography>
    </Box>
  )
}

// --- Issue list per category ----------------------------------------------
function IssueList({ label, color, issues }) {
  if (!issues?.length) return null
  return (
    <Box sx={{ mb: 2 }}>
      <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.75, mb: 0.5 }}>
        <WarningAmberIcon sx={{ fontSize: 14, color }} />
        <Typography variant="caption" fontWeight={700} sx={{ color, textTransform: 'uppercase', letterSpacing: '0.06em' }}>
          {label}
        </Typography>
      </Box>
      <List dense disablePadding>
        {issues.map((issue, i) => (
          <ListItem key={i} disablePadding sx={{ alignItems: 'flex-start' }}>
            <ListItemIcon sx={{ minWidth: 20, mt: '2px' }}>
              <ArrowRightIcon sx={{ fontSize: 14, color: 'text.disabled' }} />
            </ListItemIcon>
            <ListItemText
              primary={issue}
              primaryTypographyProps={{ variant: 'body2', color: 'text.secondary' }}
            />
          </ListItem>
        ))}
      </List>
    </Box>
  )
}

// --- Main component -------------------------------------------------------
export default function ResultsPanel({ result }) {
  if (!result) return null

  const { score = 0, feedback, brief } = result
  const { letter, color: gradeColor } = gradeFromScore(score)
  const pass = score >= 7

  return (
    <Box>
      {/* ── Score + feedback header ── */}
      <Paper elevation={2} sx={{ p: 3, mb: 2.5 }}>
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 2.5, flexWrap: 'wrap' }}>
          <ScoreBadge score={score} />
          <Box sx={{ flexGrow: 1 }}>
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 0.5 }}>
              {pass
                ? <CheckCircleIcon sx={{ fontSize: 20, color: 'success.main' }} />
                : <CancelIcon sx={{ fontSize: 20, color: 'error.main' }} />
              }
              <Typography variant="h6" fontWeight={700}>
                {pass ? 'Asset Approved' : 'Attention Required'}
              </Typography>
              <Chip
                label={`Grade ${letter}`}
                size="small"
                sx={{ bgcolor: gradeColor, color: '#fff', fontWeight: 700, fontSize: '0.68rem' }}
              />
            </Box>
            {feedback && (
              <Typography variant="body2" color="text.secondary" sx={{ lineHeight: 1.6 }}>
                {feedback}
              </Typography>
            )}
          </Box>
        </Box>
      </Paper>

      {/* ── Creative brief ── */}
      {brief && (
        <Paper elevation={2} sx={{ p: 3 }}>
          <Typography variant="h6" gutterBottom>Creative Brief</Typography>
          <Divider sx={{ mb: 2 }} />

          {brief.scope && (
            <Box sx={{ mb: 2.5 }}>
              <Typography variant="subtitle2" gutterBottom>Scope</Typography>
              <Typography variant="body2" color="text.secondary">{brief.scope}</Typography>
            </Box>
          )}

          <Grid container spacing={2} sx={{ mb: 2 }}>
            <Grid item xs={12} sm={4}>
              <IssueList label="Brand" color="#0078D4" issues={brief.brand_issues} />
            </Grid>
            <Grid item xs={12} sm={4}>
              <IssueList label="Legal" color="#7B2D8B" issues={brief.legal_issues} />
            </Grid>
            <Grid item xs={12} sm={4}>
              <IssueList label="SEO" color="#107C41" issues={brief.seo_issues} />
            </Grid>
          </Grid>

          {brief.actions?.length > 0 && (
            <>
              <Divider sx={{ mb: 2 }} />
              <Typography variant="subtitle2" gutterBottom>Recommended Actions</Typography>
              <List dense disablePadding>
                {brief.actions.map((action, i) => (
                  <ListItem key={i} disablePadding sx={{ alignItems: 'flex-start', mb: 0.5 }}>
                    <ListItemIcon sx={{ minWidth: 24, mt: '2px' }}>
                      <Box sx={{
                        width: 18, height: 18, borderRadius: '50%',
                        bgcolor: 'primary.main', color: '#fff',
                        display: 'flex', alignItems: 'center', justifyContent: 'center',
                        fontSize: '0.6rem', fontWeight: 700, flexShrink: 0,
                      }}>
                        {i + 1}
                      </Box>
                    </ListItemIcon>
                    <ListItemText
                      primary={action}
                      primaryTypographyProps={{ variant: 'body2' }}
                    />
                  </ListItem>
                ))}
              </List>
            </>
          )}
        </Paper>
      )}
    </Box>
  )
}
