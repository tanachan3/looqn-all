import { Timestamp, collection, doc, getDocs, limit, query, updateDoc } from 'firebase/firestore'
import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { db } from '../firebase'
import { formatTimestamp } from '../utils/format'
import type { Report } from '../types'

export function ReportsPage() {
  const [reports, setReports] = useState<Report[]>([])
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [processing, setProcessing] = useState<Record<string, boolean>>({})

  const normalizeReport = (docId: string, data: Record<string, unknown>): Report => {
    const postId =
      typeof data.postId === 'string'
        ? data.postId
        : typeof data.reportedPostId === 'string'
          ? data.reportedPostId
          : ''
    const reasonCode =
      typeof data.reasonCode === 'string'
        ? data.reasonCode
        : typeof data.reason === 'string'
          ? data.reason
          : undefined
    const createdAt =
      data.createdAt instanceof Timestamp
        ? data.createdAt
        : data.timestamp instanceof Timestamp
          ? data.timestamp
          : undefined
    const reporterUid =
      typeof data.reporterUid === 'string'
        ? data.reporterUid
        : typeof data.reportedBy === 'string'
          ? data.reportedBy
          : null
    const state = typeof data.state === 'string' ? data.state : 'open'
    const processed = typeof data.processed === 'boolean' ? data.processed : null

    return {
      id: docId,
      postId,
      reasonCode,
      reporterUid,
      createdAt,
      state,
      processed,
    }
  }

  const sortByCreatedAt = (items: Report[]) =>
    items.sort((a, b) => {
      const aTime = a.createdAt ? a.createdAt.toMillis() : 0
      const bTime = b.createdAt ? b.createdAt.toMillis() : 0
      return bTime - aTime
    })

  useEffect(() => {
    const load = async () => {
      try {
        const reportsQuery = query(collection(db, 'reports'), limit(200))
        const snapshot = await getDocs(reportsQuery)
        const nextReports = snapshot.docs.map((doc) => normalizeReport(doc.id, doc.data()))
        setReports(sortByCreatedAt(nextReports))
      } catch (err) {
        console.error(err)
        setError('通報一覧の取得に失敗しました。')
      } finally {
        setLoading(false)
      }
    }

    load()
  }, [])

  const handleToggleProcessed = async (reportId: string, nextValue: boolean) => {
    setProcessing((prev) => ({ ...prev, [reportId]: true }))
    setError(null)
    try {
      const reportRef = doc(db, 'reports', reportId)
      await updateDoc(reportRef, { processed: nextValue })
      setReports((prev) =>
        prev.map((report) => (report.id === reportId ? { ...report, processed: nextValue } : report)),
      )
    } catch (err) {
      console.error(err)
      setError('通報の処理済みフラグ更新に失敗しました。')
    } finally {
      setProcessing((prev) => ({ ...prev, [reportId]: false }))
    }
  }

  return (
    <section>
      <h2>通報一覧</h2>
      <p className="muted">reports コレクションの通報を新しい順に表示しています。</p>
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
            <span>処理済み</span>
          </div>
          {reports.map((report) => (
            <div key={report.id} className="table-row">
              <span>
                {report.postId ? (
                  <Link to={`/posts/${report.postId}`}>{report.postId}</Link>
                ) : (
                  '-'
                )}
              </span>
              <span>{report.reasonCode ?? '-'}</span>
              <span>{formatTimestamp(report.createdAt)}</span>
              <span>{report.state ?? 'open'}</span>
              <span>
                <button
                  className="button ghost"
                  type="button"
                  disabled={processing[report.id]}
                  onClick={() => handleToggleProcessed(report.id, !report.processed)}
                >
                  {report.processed ? '処理済み' : '未処理'}
                </button>
              </span>
            </div>
          ))}
          {reports.length === 0 && <p className="muted">通報はありません。</p>}
        </div>
      )}
    </section>
  )
}
