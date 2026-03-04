import {
  Box, Paper, Typography, Grid, Divider, Chip,
  Table, TableBody, TableCell, TableContainer,
  TableHead, TableRow, Accordion, AccordionSummary,
  AccordionDetails, Alert, Stack,
} from '@mui/material'
import ExpandMoreIcon from '@mui/icons-material/ExpandMore'
import CheckCircleIcon from '@mui/icons-material/CheckCircle'
import CancelIcon from '@mui/icons-material/Cancel'
import StatusChip from './StatusChip'

// Colour badge per category
function CategoryChip({ category }) {
  const map = {
    brand: { label: 'Brand', color: 'primary' },
    legal: { label: 'Legal', color: 'secondary' },
    seo:   { label: 'SEO',   color: 'default' },
  }
  const cfg = map[category] ?? { label: category, color: 'default' }
  return <Chip label={cfg.label} color={cfg.color} size="small" />
}

// --- Summary header -------------------------------------------------------
function SummaryHeader({ result }) {
  const { overall_pass, error_count, warning_count } = result.auditor ?? {}
  return (
    <Paper elevation={2} sx={{ p: 3, mb: 3 }}>
      <Box sx={{ display: 'flex', alignItems: 'center', gap: 2, flexWrap: 'wrap' }}>
        {overall_pass ? (
          <CheckCircleIcon sx={{ fontSize: 36, color: 'success.main' }} />
        ) : (
          <CancelIcon sx={{ fontSize: 36, color: 'error.main' }} />
        )}
        <Box sx={{ flexGrow: 1 }}>
          <Typography variant="h5" fontWeight={700}>
            {result.asset_name ?? 'Marketing Asset'}
          </Typography>
          <Typography variant="body2" color="text.secondary">
            {overall_pass ? 'Asset passed all validation checks.' : 'Asset requires attention before publishing.'}
          </Typography>
        </Box>
        <Stack direction="row" spacing={1}>
          {error_count > 0 && (
            <Chip label={`${error_count} Error${error_count !== 1 ? 's' : ''}`} color="error" />
          )}
          {warning_count > 0 && (
            <Chip label={`${warning_count} Warning${warning_count !== 1 ? 's' : ''}`} color="warning" />
          )}
          {overall_pass && <Chip label="All Checks Passed" color="success" />}
        </Stack>
      </Box>

      {result.summary && (
        <>
          <Divider sx={{ my: 2 }} />
          <Typography variant="body2" color="text.secondary">
            {result.summary}
          </Typography>
        </>
      )}
    </Paper>
  )
}

// --- Checks table ---------------------------------------------------------
function ChecksTable({ checks }) {
  if (!checks?.length) {
    return <Alert severity="info">No checks were returned.</Alert>
  }

  const failed = checks.filter((c) => !c.pass_fail)
  const passed = checks.filter((c) => c.pass_fail)

  return (
    <Box>
      {/* Failed checks — expanded by default */}
      {failed.length > 0 && (
        <Accordion defaultExpanded disableGutters elevation={0}
          sx={{ border: 1, borderColor: 'error.light', mb: 2, borderRadius: '8px !important' }}>
          <AccordionSummary expandIcon={<ExpandMoreIcon />}
            sx={{ bgcolor: 'error.50', borderRadius: '8px' }}>
            <Typography variant="subtitle2" color="error.main">
              Failed Checks ({failed.length})
            </Typography>
          </AccordionSummary>
          <AccordionDetails sx={{ p: 0 }}>
            <CheckRows rows={failed} />
          </AccordionDetails>
        </Accordion>
      )}

      {/* Passed checks — collapsed by default */}
      {passed.length > 0 && (
        <Accordion disableGutters elevation={0}
          sx={{ border: 1, borderColor: 'success.light', borderRadius: '8px !important' }}>
          <AccordionSummary expandIcon={<ExpandMoreIcon />}
            sx={{ bgcolor: 'success.50', borderRadius: '8px' }}>
            <Typography variant="subtitle2" color="success.main">
              Passed Checks ({passed.length})
            </Typography>
          </AccordionSummary>
          <AccordionDetails sx={{ p: 0 }}>
            <CheckRows rows={passed} />
          </AccordionDetails>
        </Accordion>
      )}
    </Box>
  )
}

function CheckRows({ rows }) {
  return (
    <TableContainer>
      <Table size="small">
        <TableHead>
          <TableRow>
            <TableCell>Status</TableCell>
            <TableCell>Category</TableCell>
            <TableCell>Rule</TableCell>
            <TableCell>Finding</TableCell>
            <TableCell>Recommendation</TableCell>
          </TableRow>
        </TableHead>
        <TableBody>
          {rows.map((c, i) => (
            <TableRow key={c.rule_id ?? i} hover>
              <TableCell><StatusChip pass={c.pass_fail} severity={c.severity} /></TableCell>
              <TableCell><CategoryChip category={c.category} /></TableCell>
              <TableCell><Typography variant="caption">{c.rule_id}</Typography></TableCell>
              <TableCell>
                <Typography variant="body2">{c.message}</Typography>
                {c.evidence && (
                  <Typography variant="caption" color="text.secondary" display="block">
                    Evidence: {c.evidence}
                  </Typography>
                )}
              </TableCell>
              <TableCell>
                <Typography variant="body2" color="text.secondary">
                  {c.recommendation ?? '—'}
                </Typography>
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </TableContainer>
  )
}

// --- Brief details --------------------------------------------------------
function BriefSection({ brief }) {
  if (!brief?.length) return null

  return (
    <Paper elevation={2} sx={{ p: 3, mt: 3 }}>
      <Typography variant="h6" gutterBottom>
        Creative Brief
      </Typography>
      <Divider sx={{ mb: 2 }} />
      <Grid container spacing={2}>
        {brief.map((item, i) => (
          <Grid item xs={12} sm={6} key={i}>
            <Box sx={{ p: 2, bgcolor: 'grey.50', borderRadius: 2, height: '100%' }}>
              <Typography variant="subtitle2" color="primary" gutterBottom>
                {item.section}
              </Typography>
              <Typography variant="body2">{item.content}</Typography>
              {item.priority && (
                <Chip
                  label={item.priority}
                  size="small"
                  color={item.priority === 'high' ? 'error' : item.priority === 'medium' ? 'warning' : 'default'}
                  sx={{ mt: 1 }}
                />
              )}
            </Box>
          </Grid>
        ))}
      </Grid>
    </Paper>
  )
}

// --- Main component -------------------------------------------------------
export default function ResultsPanel({ result }) {
  if (!result) return null

  const checks = result.auditor?.checks ?? []

  return (
    <Box>
      <SummaryHeader result={result} />

      <Paper elevation={2} sx={{ p: 3 }}>
        <Typography variant="h6" gutterBottom>
          Validation Checks
        </Typography>
        <ChecksTable checks={checks} />
      </Paper>

      <BriefSection brief={result.brief} />
    </Box>
  )
}
