import { collection, getDocs, limit, orderBy, query, where } from 'firebase/firestore'
import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { db } from '../firebase'
import { formatTimestamp } from '../utils/format'
import type { Report } from '../types'

export function ReportsPage() {
  const [reports, setReports] = useState<Report[]>([])
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    const load = async () => {
      try {
        const reportsQuery = query(
          collection(db, 'reports'),
          where('state', '==', 'open'),
          orderBy('createdAt', 'desc'),
          limit(50),
        )
        const snapshot = await getDocs(reportsQuery)
        const nextReports = snapshot.docs.map((doc) => ({
          id: doc.id,
          ...(doc.data() as Omit<Report, 'id'>),
        }))
        setReports(nextReports)
      } catch (err) {
        console.error(err)
        setError('通報キューの取得に失敗しました。')
      } finally {
        setLoading(false)
      }
    }

    load()
  }, [])

  return (
    <section>
      <h2>通報キュー</h2>
      <p className="muted">最新の open 通報のみを表示しています。</p>
      {error && <p className="alert">{error}</p>}
      {loading ? (
        <p>読み込み中...</p>
      ) : (
        <div className="table">
          <div className="table-row header">
            <span>投稿ID</span>
            <span>理由</span>
            <span>通報日時</span>
            <span>状態</span>
          </div>
          {reports.map((report) => (
            <div key={report.id} className="table-row">
              <span>
                <Link to={`/posts/${report.postId}`}>{report.postId}</Link>
              </span>
              <span>{report.reasonCode ?? '-'}</span>
              <span>{formatTimestamp(report.createdAt)}</span>
              <span>{report.state ?? 'open'}</span>
            </div>
          ))}
          {reports.length === 0 && <p className="muted">通報はありません。</p>}
        </div>
      )}
    </section>
  )
}
