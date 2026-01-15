import {
  collection,
  doc,
  getDoc,
  getDocs,
  orderBy,
  query,
  where,
} from 'firebase/firestore'
import { useEffect, useState } from 'react'
import { useParams } from 'react-router-dom'
import { replyInquiry, updateInquiry } from '../api/functions'
import { db } from '../firebase'
import type { Inquiry, InquiryMessage } from '../types'
import { formatTimestamp } from '../utils/format'

export function InquiryDetailPage() {
  const { id } = useParams()
  const [inquiry, setInquiry] = useState<Inquiry | null>(null)
  const [messages, setMessages] = useState<InquiryMessage[]>([])
  const [replyText, setReplyText] = useState('')
  const [assigneeUid, setAssigneeUid] = useState('')
  const [state, setState] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)

  const fetchInquiry = async () => {
    if (!id) return
    const inquirySnap = await getDoc(doc(db, 'inquiries', id))
    if (inquirySnap.exists()) {
      const data = inquirySnap.data() as Omit<Inquiry, 'id'>
      setInquiry({ id: inquirySnap.id, ...data })
      setAssigneeUid(data.assigneeUid ?? '')
      setState(data.state ?? '')
    } else {
      setInquiry(null)
    }
  }

  const fetchMessages = async () => {
    if (!id) return
    const messageQuery = query(
      collection(db, 'inquiry_messages'),
      where('inquiryId', '==', id),
      orderBy('createdAt', 'asc'),
    )
    const messageSnap = await getDocs(messageQuery)
    const list = messageSnap.docs.map((docSnap) => ({
      id: docSnap.id,
      ...(docSnap.data() as Omit<InquiryMessage, 'id'>),
    }))
    setMessages(list)
  }

  useEffect(() => {
    const load = async () => {
      try {
        await Promise.all([fetchInquiry(), fetchMessages()])
      } catch (err) {
        console.error(err)
        setError('問い合わせ情報の取得に失敗しました。')
      }
    }

    load()
  }, [id])

  const handleReply = async () => {
    if (!id || !replyText.trim()) return
    try {
      setError(null)
      setMessage(null)
      await replyInquiry({ inquiryId: id, text: replyText })
      setReplyText('')
      setMessage('返信を送信しました。')
      await fetchMessages()
    } catch (err) {
      console.error(err)
      setError('返信の送信に失敗しました。')
    }
  }

  const handleUpdate = async () => {
    if (!id) return
    try {
      setError(null)
      setMessage(null)
      await updateInquiry({
        inquiryId: id,
        state: state || undefined,
        assigneeUid: assigneeUid || undefined,
      })
      setMessage('問い合わせ情報を更新しました。')
      await fetchInquiry()
    } catch (err) {
      console.error(err)
      setError('更新に失敗しました。')
    }
  }

  if (!id) {
    return <p className="alert">問い合わせIDが見つかりません。</p>
  }

  return (
    <section>
      <h2>問い合わせ詳細</h2>
      <p className="muted">スレッド内容と担当状況を管理します。</p>
      {error && <p className="alert">{error}</p>}
      {message && <p className="success">{message}</p>}

      <div className="panel">
        <h3>問い合わせ情報</h3>
        {inquiry ? (
          <dl className="detail">
            <div>
              <dt>ID</dt>
              <dd>{inquiry.id}</dd>
            </div>
            <div>
              <dt>状態</dt>
              <dd>{inquiry.state ?? '-'}</dd>
            </div>
            <div>
              <dt>カテゴリ</dt>
              <dd>{inquiry.category ?? '-'}</dd>
            </div>
            <div>
              <dt>担当者</dt>
              <dd>{inquiry.assigneeUid ?? '-'}</dd>
            </div>
            <div>
              <dt>最終更新</dt>
              <dd>{formatTimestamp(inquiry.lastMessageAt)}</dd>
            </div>
          </dl>
        ) : (
          <p>問い合わせ情報が見つかりません。</p>
        )}
      </div>

      <div className="panel">
        <h3>ステータス更新</h3>
        <div className="form">
          <label>
            state
            <select value={state} onChange={(event) => setState(event.target.value)}>
              <option value="">変更なし</option>
              <option value="new">new</option>
              <option value="assigned">assigned</option>
              <option value="waiting_user">waiting_user</option>
              <option value="done">done</option>
            </select>
          </label>
          <label>
            assigneeUid
            <input
              value={assigneeUid}
              onChange={(event) => setAssigneeUid(event.target.value)}
              placeholder="担当UID"
            />
          </label>
        </div>
        <button className="button" onClick={handleUpdate}>
          更新
        </button>
      </div>

      <div className="panel">
        <h3>返信</h3>
        <textarea
          className="textarea"
          value={replyText}
          onChange={(event) => setReplyText(event.target.value)}
          placeholder="返信内容を入力してください。"
        />
        <button className="button" onClick={handleReply}>
          返信を送信
        </button>
      </div>

      <div className="panel">
        <h3>スレッド</h3>
        <div className="messages">
          {messages.map((item) => (
            <div key={item.id} className={`message ${item.senderType}`}>
              <div className="meta">
                <span>{item.senderType}</span>
                <span>{formatTimestamp(item.createdAt)}</span>
              </div>
              <p>{item.text}</p>
            </div>
          ))}
        </div>
        {messages.length === 0 && <p className="muted">メッセージはありません。</p>}
      </div>
    </section>
  )
}
