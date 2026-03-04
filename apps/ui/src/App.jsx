import { useState } from 'react'
import { Box, AppBar, Toolbar, Typography, Container, Grid } from '@mui/material'
import AutoAwesomeIcon from '@mui/icons-material/AutoAwesome'
import UploadPanel from './components/UploadPanel'
import ResultsPanel from './components/ResultsPanel'
import { validateAsset } from './api/client'

export default function App() {
  const [status, setStatus] = useState('idle') // idle | loading | success | error
  const [result, setResult] = useState(null)
  const [errorMsg, setErrorMsg] = useState('')

  async function handleValidate(file) {
    setStatus('loading')
    setResult(null)
    setErrorMsg('')
    try {
      const data = await validateAsset(file)
      setResult(data)
      setStatus('success')
    } catch (err) {
      setErrorMsg(err.message ?? 'Validation failed. Please try again.')
      setStatus('error')
    }
  }

  function handleReset() {
    setStatus('idle')
    setResult(null)
    setErrorMsg('')
  }

  return (
    <Box sx={{ minHeight: '100vh', bgcolor: 'background.default' }}>
      {/* Top bar */}
      <AppBar position="static" elevation={0} sx={{ bgcolor: 'primary.main' }}>
        <Toolbar>
          <AutoAwesomeIcon sx={{ mr: 1.5 }} />
          <Typography variant="h6" component="div" sx={{ flexGrow: 1, fontWeight: 700 }}>
            BrandSense
          </Typography>
          <Typography variant="body2" sx={{ opacity: 0.8 }}>
            AI Marketing Asset Validation
          </Typography>
        </Toolbar>
      </AppBar>

      <Container maxWidth="xl" sx={{ py: 4 }}>
        <Grid container spacing={3}>
          {/* Upload panel — always visible */}
          <Grid item xs={12} md={result ? 4 : 6} lg={result ? 3 : 5}
            sx={{ mx: result ? 0 : 'auto', transition: 'all 0.3s ease' }}>
            <UploadPanel
              status={status}
              onValidate={handleValidate}
              onReset={handleReset}
              errorMsg={errorMsg}
            />
          </Grid>

          {/* Results panel — visible after validation */}
          {result && (
            <Grid item xs={12} md={8} lg={9}>
              <ResultsPanel result={result} />
            </Grid>
          )}
        </Grid>
      </Container>
    </Box>
  )
}
