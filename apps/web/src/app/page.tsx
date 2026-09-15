import { HomeClient } from "./HomeClient";

/**
 * 首页：纯服务端入口，直接转发到客户端分发逻辑（首访 → /grade/1/，有教材 → /book/）
 */
export default function HomePage() {
  return <HomeClient />;
}
