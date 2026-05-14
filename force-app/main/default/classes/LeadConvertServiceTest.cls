@isTest
private class LeadConvertServiceTest {

    @isTest
    static void testConvertLead() {
        User adminUser = [
            SELECT Id FROM User
            WHERE Name = 'Widsley Admin'
            AND IsActive = true
            LIMIT 1
        ];

        Lead lead = new Lead(
            LastName = 'テスト',
            FirstName = '太郎',
            Company = 'テスト株式会社',
            Email = 'test-convert@example.com',
            Phone = '09012345678',
            User__c = adminUser.Id
        );
        insert lead;

        Lead converted = [SELECT Id, IsConverted FROM Lead WHERE Id = :lead.Id];
        System.assertEquals(true, converted.IsConverted, 'リードが取引開始されていること');
    }
}