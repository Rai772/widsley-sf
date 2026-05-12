public class LeadFilterService {

    // ─── いたずら判定 ───────────────────────────────
    public static Boolean isSpam(Lead lead) {
        return isInvalidPhone(lead.Phone);
    }

    private static Boolean isInvalidPhone(String phone) {
        if (String.isBlank(phone)) return true;
        String digits = phone.replaceAll('[^0-9]', '');
        return digits.length() < 10 || digits.length() > 11;
    }

    // ─── いたずら時のリード更新 ──────────────────────
    public static void markAsSpam(Lead lead, String currentTouchpoint) {
        lead.Status = 'アーカイブ';
        lead.first_touchpoint__c = resolveInvalidTouchpoint(currentTouchpoint);
    }

    // ─── 初回流入経路を無効用の値に変換 ──────────────
    public static String resolveInvalidTouchpoint(String touchpoint) {
        if (touchpoint == null) return '逆営業と無効';
        if (touchpoint.contains('アスピック'))   return 'アスピック（逆営業と無効）';
        if (touchpoint.contains('アイミツ'))     return 'アイミツSaaS（逆営業と無効）';
        if (touchpoint.contains('ミツモア'))     return 'ミツモア（逆営業と無効）';
        return '逆営業と無効';
    }
}