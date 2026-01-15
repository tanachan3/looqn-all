import { collection, getDocs, limit, orderBy, query } from 'firebase/firestore'
import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { db } from '../firebase'
import type { Inquiry } from '../types'
import { formatTimestamp } from '../utils/format'

export function InquiriesPage() {
  const [inquiries, setInquiries] = useState<Inquiry[]>([])
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    const load = async () => {
      try {
        const inquiryQuery = query(
          collection(db, 'inquiries'),
          orderBy('lastMessageAt', 'desc'),
          limit(50),
        )
        const snapshot = await getDocs(inquiryQuery)
        const list = snapshot.docs.map((docSnap) => ({
          id: docSnap.id,
          ...(docSnap.data() as Omit<Inquiry, 'id'>),
        }))
        setInquiries(list)
      } catch (err) {
        console.error(err)
        setError('問い合わせ一覧の取得に失敗しました。')
      } finally {
        setLoading(false)
      }
    }

    load()
  }, [])

  return (
    <section>
      <h2>問い合わせ一覧</h2>
      <p className="muted">最新の問い合わせを表示しています。</p>
      {error && <p className="alert">{error}</p>}
      {loading ? (
        <p>読み込み中...</p>
      ) : (
        <div className="table">
          <div className="table-row header">
            <span>ID</span>
            <span>状態</span>
            <span>担当者</span>
            <span>最終更新</span>
          </div>
          {inquiries.map((inquiry) => (
            <div key={inquiry.id} className="table-row">
              <span>
                <Link to={`/inquiries/${inquiry.id}`}>{inquiry.id}</Link>
              </span>
              <span>{inquiry.state ?? '-'}</span>
              <span>{inquiry.assigneeUid ?? '-'}</span>
              <span>{formatTimestamp(inquiry.lastMessageAt)}</span>
            </div>
          ))}
          {inquiries.length === 0 && <p className="muted">問い合わせはありません。</p>}
        </div>
      )}
    </section>
  )
}
