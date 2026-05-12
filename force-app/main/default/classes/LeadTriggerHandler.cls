public class LeadTriggerHandler {

    public static void afterInsert(List<Lead> newLeads) {
        List<Lead> leadsToUpdate = new List<Lead>();

        for (Lead lead : newLeads) {

            Lead updatedLead = new Lead(Id = lead.Id);
            Boolean needsUpdate = false;

            // ─── ① いたずらチェック ───────────────────
            if (LeadFilterService.isSpam(lead)) {
                String source = lead.first_touchpoint__c != null
                    ? lead.first_touchpoint__c
                    : '問い合わせ';
                LeadFilterService.markAsSpam(updatedLead, source);
                needsUpdate = true;
            }

            if (needsUpdate) {
                leadsToUpdate.add(updatedLead);
            }
        }

        if (!leadsToUpdate.isEmpty()) {
            update leadsToUpdate;
        }
    }
}