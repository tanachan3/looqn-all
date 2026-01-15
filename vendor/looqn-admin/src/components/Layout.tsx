import { NavLink, Outlet } from 'react-router-dom'
import { useAuth } from '../auth/AuthContext'

export function Layout() {
  const { user, role, signOutUser } = useAuth()

  return (
    <div className="app-shell">
      <header className="header">
        <div>
          <h1>LooQN Admin</h1>
          <p className="sub">運用オペレーターコンソール</p>
        </div>
        <div className="user-box">
          <div>
            <div className="user-label">{user?.email ?? '未ログイン'}</div>
            <div className="user-role">role: {role ?? 'none'}</div>
          </div>
          <button className="button ghost" onClick={signOutUser}>
            ログアウト
          </button>
        </div>
      </header>
      <div className="body">
        <nav className="sidebar">
          <NavLink to="/" end>
            ダッシュボード
          </NavLink>
          <NavLink to="/reports">通報キュー</NavLink>
          <NavLink to="/posts">投稿検索</NavLink>
          <NavLink to="/inquiries">問い合わせ</NavLink>
          <NavLink to="/settings">設定</NavLink>
        </nav>
        <main className="content">
          <Outlet />
        </main>
      </div>
    </div>
  )
}
