import { Navigate, Outlet } from 'react-router-dom'
import { useAuth } from './AuthContext'
import { LoadingScreen } from '../components/LoadingScreen'

export function AuthGuard() {
  const { user, role, loading } = useAuth()

  if (loading) {
    return <LoadingScreen message="認証状態を確認しています..." />
  }

  if (!user) {
    return <Navigate to="/login" replace />
  }

  if (!role) {
    return <Navigate to="/login" replace state={{ unauthorized: true }} />
  }

  return <Outlet />
}
