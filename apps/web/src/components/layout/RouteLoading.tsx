/**
 * RouteLoading —— 动态路由加载骨架。
 *
 * 静态导出下客户端导航到动态路由（/book/*、/grade/*、/lesson/*）时，
 * Next 会先拉取该路由的 RSC 载荷，期间没有 loading.tsx 就是一片空白。
 * 这里给一层与整体风格一致的骨架占位，避免“先没有内容再加载出来”的断层。
 */
export function RouteLoading() {
  return (
    <div className="animate-pulse w-full max-w-4xl mx-auto px-4 py-6 space-y-6">
      {/* 页头占位 */}
      <div className="flex items-center gap-4">
        <div className="h-12 w-12 rounded-2xl bg-bg-softer" />
        <div className="space-y-2">
          <div className="h-4 w-40 rounded-full bg-bg-softer" />
          <div className="h-3 w-24 rounded-full bg-bg-soft" />
        </div>
      </div>

      {/* 内容卡片网格 */}
      <div className="grid gap-3 sm:grid-cols-2">
        {Array.from({ length: 6 }).map((_, i) => (
          <div key={i} className="rounded-3xl border border-bg-softer bg-bg-soft p-4 space-y-3">
            <div className="h-3 w-2/3 rounded-full bg-bg-softer" />
            <div className="h-3 w-1/2 rounded-full bg-bg-soft" />
            <div className="h-8 w-24 rounded-xl bg-bg-softer" />
          </div>
        ))}
      </div>
    </div>
  );
}