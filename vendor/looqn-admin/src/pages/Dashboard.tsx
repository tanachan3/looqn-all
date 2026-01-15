import { collection, getCountFromServer, query, where } from 'firebase/firestore'
import { useEffect, useState } from 'react'
import { db } from '../firebase'

type Summary = {
  openReports: number
  newInquiries: number
  assignedInquiries: number
}

export function DashboardPage() {
  const [summary, setSummary] = useState<Summary | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    const load = async () => {
      try {
        const openReportsQuery = query(collection(db, 'reports'), where('state', '==', 'open'))
        const newInquiriesQuery = query(collection(db, 'inquiries'), where('state', '==', 'new'))
        const assignedInquiriesQuery = query(
          collection(db, 'inquiries'),
          where('state', '==', 'assigned'),
        )

        const [openReports, newInquiries, assignedInquiries] = await Promise.all([
          getCountFromServer(openReportsQuery),
          getCountFromServer(newInquiriesQuery),
          getCountFromServer(assignedInquiriesQuery),
        ])

        setSummary({
          openReports: openReports.data().count,
          newInquiries: newInquiries.data().count,
          assignedInquiries: assignedInquiries.data().count,
        })
      } catch (err) {
        console.error(err)
        setError('ダッシュボード情報の取得に失敗しました。')
      }
    }

    load()
  }, [])

  return (
    <section>
      <h2>ダッシュボード</h2>
      <p className="muted">現在のキュー状況を表示します。</p>
      {error && <p className="alert">{error}</p>}
      <div className="grid">
        <div className="card">
          <h3>未処理の通報</h3>
          <p className="metric">{summary ? summary.openReports : '...'}</p>
        </div>
        <div className="card">
          <h3>新規問い合わせ</h3>
          <p className="metric">{summary ? summary.newInquiries : '...'}</p>
        </div>
        <div className="card">
          <h3>担当中の問い合わせ</h3>
          <p className="metric">{summary ? summary.assignedInquiries : '...'}</p>
        </div>
      </div>
    </section>
  )
}
