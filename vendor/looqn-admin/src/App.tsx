import { BrowserRouter, Route, Routes } from 'react-router-dom'
import { AuthGuard } from './auth/AuthGuard'
import { Layout } from './components/Layout'
import { DashboardPage } from './pages/Dashboard'
import { InquiryDetailPage } from './pages/InquiryDetail'
import { InquiriesPage } from './pages/Inquiries'
import { LoginPage } from './pages/Login'
import { NotFoundPage } from './pages/NotFound'
import { PostDetailPage } from './pages/PostDetail'
import { PostsSearchPage } from './pages/PostsSearch'
import { ReportsPage } from './pages/Reports'
import { SettingsPage } from './pages/Settings'
import { UsersPage } from './pages/Users'

function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/login" element={<LoginPage />} />
        <Route element={<AuthGuard />}>
          <Route element={<Layout />}>
            <Route index element={<DashboardPage />} />
            <Route path="/reports" element={<ReportsPage />} />
            <Route path="/posts" element={<PostsSearchPage />} />
            <Route path="/posts/:postId" element={<PostDetailPage />} />
            <Route path="/inquiries" element={<InquiriesPage />} />
            <Route path="/inquiries/:id" element={<InquiryDetailPage />} />
            <Route path="/users" element={<UsersPage />} />
            <Route path="/settings" element={<SettingsPage />} />
          </Route>
        </Route>
        <Route path="*" element={<NotFoundPage />} />
      </Routes>
    </BrowserRouter>
  )
}

export default App
