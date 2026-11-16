export async function onRequestGet(context) {
  const origin = new URL(context.request.url).origin;
  const depictionJSON = {
    minVersion: "0.4",
    headerImage: origin + "/shots/1-nhieu-app-dark.jpg",
    tintColor: "#007AFF",
    tabs: [
      {
        tabname: "Chi tiết",
        views: [
          { class: "DepictionSubheaderView", useBoldText: true, title: "XemYouTube — Đa nhiệm chia đôi màn hình & Bong bóng tốc độ cho CarPlay" },
          { class: "DepictionMarkdownView", markdown: "- **Chia đôi màn hình:** Mở 2 ứng dụng song song trên màn hình xe.\n- **Bong bóng tốc độ:** Hiển thị tốc độ GPS & biển báo giao thông.\n- **Tin nhắn trực tiếp:** Xem nội dung tin nhắn ngay trên màn hình xe." }
        ]
      }
    ]
  };
  return new Response(JSON.stringify(depictionJSON), { headers: { "Content-Type": "application/json; charset=utf-8", "Access-Control-Allow-Origin": "*" } });
}
