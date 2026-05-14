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

    public static void markAsSpam(Lead lead, String currentTouchpoint) {
        lead.Status = 'アーカイブ';
        lead.first_touchpoint__c = resolveInvalidTouchpoint(currentTouchpoint);
    }

    public static String resolveInvalidTouchpoint(String touchpoint) {
        if (touchpoint == null) return '逆営業と無効';
        if (touchpoint.contains('アスピック'))   return 'アスピック（逆営業と無効）';
        if (touchpoint.contains('アイミツ'))     return 'アイミツSaaS（逆営業と無効）';
        if (touchpoint.contains('ミツモア'))     return 'ミツモア（逆営業と無効）';
        return '逆営業と無効';
    }

    // ─── 重複 / 再流入チェック ──────────────────────
    public static Map<String, Object> checkDuplicate(Lead lead) {
        Map<String, Object> result = new Map<String, Object>{
            'isDuplicate' => false,
            'isReflow'    => false,
            'existingLead'    => null,
            'existingContact' => null
        };

        if (String.isBlank(lead.Email) && String.isBlank(lead.Phone)) {
            return result;
        }

        Date sixMonthsAgo = Date.today().addMonths(-6);

        List<Lead> existingLeads = [
            SELECT Id, Email, Phone, Remarks__c, LeadSourceDate__c
            FROM Lead
            WHERE Id != :lead.Id
            AND (Email = :lead.Email OR Phone = :lead.Phone)
            AND IsConverted = false
            ORDER BY LeadSourceDate__c DESC
            LIMIT 1
        ];

        if (!existingLeads.isEmpty()) {
            Lead existing = existingLeads[0];
            result.put('existingLead', existing);
            if (existing.LeadSourceDate__c == null) {
                return result;
            }
            if (existing.LeadSourceDate__c >= sixMonthsAgo) {
                result.put('isDuplicate', true);
            } else {
                result.put('isReflow', true);
            }
            return result;
        }

        List<Contact> existingContacts = [
            SELECT Id, Email, Phone, LeadSourceDate__c
            FROM Contact
            WHERE (Email = :lead.Email OR Phone = :lead.Phone)
            ORDER BY LeadSourceDate__c DESC
            LIMIT 1
        ];

        if (!existingContacts.isEmpty()) {
            Contact existing = existingContacts[0];
            result.put('existingContact', existing);
            if (existing.LeadSourceDate__c != null && existing.LeadSourceDate__c >= sixMonthsAgo) {
                result.put('isDuplicate', true);
            } else {
                result.put('isReflow', true);
            }
        }

        return result;
    }

    // ─── 重複/再流入時の備考追記 ─────────────────────
    public static void appendRemarks(SObject record, String label, Lead newLead) {
        String today = String.valueOf(Date.today());
        String touchpoint = String.isBlank(newLead.first_touchpoint__c) ? 'ホームページ' : newLead.first_touchpoint__c;
        String suffix = label == '重複'
            ? touchpoint + 'より重複問い合わせあり（' + today + '）'
            : touchpoint + 'より再流入問い合わせあり（' + today + '）';
    
        String newEntry = '';
        if (!String.isBlank(newLead.Description)) newEntry += newLead.Description + '\n';
        if (!String.isBlank(newLead.web__c))      newEntry += newLead.web__c + '\n';
        newEntry += suffix;
    
        String currentRemarks = (String) record.get('Remarks__c');
        if (String.isBlank(currentRemarks)) {
            record.put('Remarks__c', newEntry);
        } else {
            record.put('Remarks__c', currentRemarks + '\n' + newEntry);
        }
    }

    // ─── 既存顧客判定 ───────────────────────────────
    public static Boolean isExistingCustomer(Lead lead) {
        if (String.isBlank(lead.Email) && String.isBlank(lead.Phone)) {
            return false;
        }

        List<Contact> contacts = [
            SELECT Id, AccountId
            FROM Contact
            WHERE (Email = :lead.Email OR Phone = :lead.Phone)
            LIMIT 1
        ];

        if (contacts.isEmpty()) return false;

        List<Contract__c> contracts = [
            SELECT Id, churn_status__c
            FROM Contract__c
            WHERE AccountId__c = :contacts[0].AccountId
            AND churn_status__c = ''
            LIMIT 1
        ];

        return !contracts.isEmpty();
    }

    public static void markAsExistingCustomer(Lead lead) {
        lead.IsExistingCustomer__c = true;
    }
}