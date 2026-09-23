/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{vue,js}'],
  theme: {
    extend: {
      colors: {
        fp: { 25:'#F4FAF6', 50:'#EAF6EF', 100:'#D6EEDF', 200:'#B4DFC6', 300:'#86C9A3', 400:'#4FAE7C', 500:'#2C9663', 600:'#1D8A55', 700:'#177347', 800:'#145C3B', 900:'#114A31' },
        paper: '#FBFBF9', line: '#E6E9E2', ink: '#20241F', mut: '#68705F'
      },
      fontFamily: {
        sans: ['Public Sans', 'system-ui', '-apple-system', 'Segoe UI', 'sans-serif'],
        serif: ['Source Serif 4', 'Georgia', 'serif']
      }
    }
  },
  plugins: []
};
