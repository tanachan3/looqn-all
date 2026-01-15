export function LoadingScreen({ message }: { message?: string }) {
  return (
    <div className="panel center">
      <p>{message ?? '読み込み中...'} </p>
    </div>
  )
}
