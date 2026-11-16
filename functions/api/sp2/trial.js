export async function onRequestPost(context) {
  try {
    const { code } = await context.request.json();
    const cleanCode = (code || "").trim().toUpperCase();
    if (!cleanCode || cleanCode.length < 6) {
      return Response.json({ success: false, message: "Mã kích hoạt không hợp lệ!" }, { status: 400 });
    }
    const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString().split("T")[0];
    return Response.json({ success: true, message: "Kích hoạt thành công 30 ngày dùng thử! (Hạn: " + expiresAt + ")", expires_at: expiresAt });
  } catch (e) {
    return Response.json({ success: false, message: "Yêu cầu không hợp lệ." }, { status: 500 });
  }
}
