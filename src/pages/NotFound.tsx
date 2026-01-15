import { Link } from 'react-router-dom'

export function NotFoundPage() {
  return (
    <div className="panel center">
      <h2>ページが見つかりません</h2>
      <p className="muted">URL を確認してください。</p>
      <Link to="/" className="button">
        ダッシュボードへ戻る
      </Link>
    </div>
  )
}
