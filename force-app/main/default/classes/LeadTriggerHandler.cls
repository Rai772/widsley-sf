public class LeadTriggerHandler {

    public static void afterInsert(List<Lead> newLeads) {
        List<Lead> leadsToUpdate = new List<Lead>();
        List<Contact> contactsToUpdate = new List<Contact>();

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
                if (isReflow) {
                    updatedLead.IsReflow__c = true;
                }
                needsUpdate = true;

                Lead existingLead = (Lead) dupResult.get('existingLead');
                if (existingLead != null) {
                    Lead existingToUpdate = new Lead(Id = existingLead.Id);
                    LeadFilterService.appendRemarks(existingToUpdate, label, lead);
                    if (isReflow) {
                        updatedLead.ReflowSourceLeadId__c = existingLead.Id;
                        existingToUpdate.IsReflow__c = true;
                    }
                    leadsToUpdate.add(existingToUpdate);
                } else {
                    Contact existingContact = (Contact) dupResult.get('existingContact');
                    if (existingContact != null) {
                        Contact contactToUpdate = new Contact(Id = existingContact.Id);
                        LeadFilterService.appendRemarks(contactToUpdate, label, lead);
                        if (isReflow) {
                            contactToUpdate.IsReflow__c = true;
                        }
                        contactsToUpdate.add(contactToUpdate);
                    }
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

            // ─── ⑥ 有効リード → 取引開始 ───────────────
            LeadConvertService.convertLead(lead);

            if (needsUpdate) {
                leadsToUpdate.add(updatedLead);
            }
        }

        if (!leadsToUpdate.isEmpty()) {
            update leadsToUpdate;
        }
        if (!contactsToUpdate.isEmpty()) {
            update contactsToUpdate;
        }
    }
}