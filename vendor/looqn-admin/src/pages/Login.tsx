import { useEffect } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { useAuth } from '../auth/AuthContext'
import { LoadingScreen } from '../components/LoadingScreen'

export function LoginPage() {
  const { user, role, loading, signInWithGoogle, error } = useAuth()
  const navigate = useNavigate()
  const location = useLocation()
  const unauthorized = Boolean(location.state && (location.state as { unauthorized?: boolean }).unauthorized)

  useEffect(() => {
    if (!loading && user && role) {
      navigate('/')
    }
  }, [loading, user, role, navigate])

  if (loading) {
    return <LoadingScreen message="ログイン状態を確認しています..." />
  }

  return (
    <div className="login">
      <div className="panel">
        <h2>LooQN 管理画面</h2>
        <p className="muted">Google アカウントでログインしてください。</p>
        {unauthorized && (
          <p className="alert">権限がありません。管理者に role を付与してもらってください。</p>
        )}
        {error && <p className="alert">{error}</p>}
        <button className="button" onClick={signInWithGoogle}>
          Google でログイン
        </button>
      </div>
    </div>
  )
}
