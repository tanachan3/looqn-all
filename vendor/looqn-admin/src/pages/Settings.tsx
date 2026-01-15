import { useAuth } from '../auth/AuthContext'

export function SettingsPage() {
  const { user, role, refreshClaims, error } = useAuth()

  return (
    <section>
      <h2>設定</h2>
      <p className="muted">ログイン情報と権限を確認します。</p>
      {error && <p className="alert">{error}</p>}
      <div className="panel">
        <dl className="detail">
          <div>
            <dt>Email</dt>
            <dd>{user?.email ?? '-'}</dd>
          </div>
          <div>
            <dt>UID</dt>
            <dd>{user?.uid ?? '-'}</dd>
          </div>
          <div>
            <dt>Role</dt>
            <dd>{role ?? 'none'}</dd>
          </div>
        </dl>
        <button className="button" onClick={refreshClaims}>
          権限を再取得
        </button>
      </div>
    </section>
  )
}
