import { createTheme } from '@mui/material/styles'

// BrandSense theme — Microsoft brand colours
const theme = createTheme({
  palette: {
    primary: {
      main:        '#0078D4',
      dark:        '#005a9e',
      light:       '#2b88d8',
      contrastText: '#ffffff',
    },
    secondary: {
      main: '#50E6FF',
    },
    background: {
      default: '#f0f2f5',
      paper:   '#ffffff',
    },
    sidebar: {
      bg:          '#0f2027',
      hover:       'rgba(255,255,255,0.08)',
      active:      'rgba(0,120,212,0.25)',
      activeBorder: '#0078D4',
      text:        'rgba(255,255,255,0.85)',
      textMuted:   'rgba(255,255,255,0.45)',
    },
    error:   { main: '#D32F2F', light: '#ef9a9a', '50': '#ffebee' },
    warning: { main: '#F59E0B', light: '#ffe082', '50': '#fffde7' },
    success: { main: '#16A34A', light: '#a5d6a7', '50': '#e8f5e9' },
  },
  typography: {
    fontFamily: '"Segoe UI", Roboto, Arial, sans-serif',
    h4:       { fontWeight: 700 },
    h5:       { fontWeight: 700 },
    h6:       { fontWeight: 600 },
    subtitle1:{ fontWeight: 600 },
    subtitle2:{ fontWeight: 600 },
  },
  shape: { borderRadius: 8 },
  components: {
    MuiPaper: {
      styleOverrides: {
        root: { backgroundImage: 'none' },
      },
    },
    MuiTableCell: {
      styleOverrides: {
        head: { fontWeight: 600, backgroundColor: '#f8f9fa' },
      },
    },
  },
})

export default theme
