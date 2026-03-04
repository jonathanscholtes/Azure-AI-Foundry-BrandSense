import { createTheme } from '@mui/material/styles'

// BrandSense theme — Microsoft brand colours
const theme = createTheme({
  palette: {
    primary: {
      main: '#0078D4',
      contrastText: '#ffffff',
    },
    secondary: {
      main: '#50E6FF',
    },
    background: {
      default: '#f5f5f5',
      paper: '#ffffff',
    },
    error:   { main: '#D32F2F' },
    warning: { main: '#F59E0B' },
    success: { main: '#16A34A' },
  },
  typography: {
    fontFamily: '"Segoe UI", Roboto, Arial, sans-serif',
    h4: { fontWeight: 700 },
    h6: { fontWeight: 600 },
    subtitle2: { fontWeight: 600 },
  },
  shape: { borderRadius: 8 },
})

export default theme
