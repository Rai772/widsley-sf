public class LeadConvertService {

    public static void convertLead(Lead lead) {
        User adminUser = [
            SELECT Id FROM User
            WHERE Name = 'Widsley Admin'
            AND IsActive = true
            LIMIT 1
        ];

        Database.LeadConvert lc = new Database.LeadConvert();
        lc.setLeadId(lead.Id);
        lc.setOwnerId(adminUser.Id);
        lc.setDoNotCreateOpportunity(true);
        lc.setConvertedStatus('商談化');

        Database.convertLead(lc);
    }
}