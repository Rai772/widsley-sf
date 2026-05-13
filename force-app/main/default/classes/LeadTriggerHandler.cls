public class LeadTriggerHandler {

    public static void afterInsert(List<Lead> newLeads) {
        List<Lead> leadsToUpdate = new List<Lead>();

        for (Lead lead : newLeads) {
            Lead updatedLead = new Lead(Id = lead.Id);
            Boolean needsUpdate = false;

            // ─── ① 既存顧客チェック ──────────────────
            if (LeadFilterService.isExistingCustomer(lead)) {
                LeadFilterService.markAsExistingCustomer(updatedLead);
                needsUpdate = true;
                leadsToUpdate.add(updatedLead);
                continue;
            }

            // ─── ② 重複 / 再流入チェック ─────────────
            Map<String, Object> dupResult = LeadFilterService.checkDuplicate(lead);
            Boolean isDuplicate = (Boolean) dupResult.get('isDuplicate');
            Boolean isReflow    = (Boolean) dupResult.get('isReflow');

            if (isDuplicate || isReflow) {
                String label = isDuplicate ? '重複' : '再流入';
                updatedLead.Status = 'アーカイブ';
                needsUpdate = true;

                Lead existingLead = (Lead) dupResult.get('existingLead');
                if (existingLead != null) {
                    Lead existingToUpdate = new Lead(Id = existingLead.Id);
                    LeadFilterService.appendRemarks(existingToUpdate, label);
                    leadsToUpdate.add(existingToUpdate);
                }
                leadsToUpdate.add(updatedLead);
                continue;
            }

            // ─── ③ いたずらチェック ───────────────────
            if (LeadFilterService.isSpam(lead)) {
                LeadFilterService.markAsSpam(updatedLead, lead.first_touchpoint__c);
                needsUpdate = true;
                leadsToUpdate.add(updatedLead);
                continue;
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