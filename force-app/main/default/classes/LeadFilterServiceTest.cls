@isTest
public class LeadFilterServiceTest {

    @isTest
    static void testSpam_invalidPhone_aspic() {
        Lead lead = new Lead(
            LastName            = 'テスト',
            Company             = 'テスト会社',
            Email               = 'test@example.com',
            Phone               = '123',
            first_touchpoint__c = 'アスピック'
        );
        insert lead;
        Lead result = [SELECT Status, first_touchpoint__c FROM Lead WHERE Id = :lead.Id];
        System.assertEquals('アーカイブ', result.Status);
        System.assertEquals('アスピック（逆営業と無効）', result.first_touchpoint__c);
    }

    @isTest
    static void testSpam_validPhone() {
        Lead lead = new Lead(
            LastName = 'テスト2',
            Company  = 'テスト会社',
            Email    = 'test2@example.com',
            Phone    = '09012345678'
        );
        insert lead;
        Lead result = [SELECT Status FROM Lead WHERE Id = :lead.Id];
        System.assertNotEquals('アーカイブ', result.Status);
    }

    @isTest
    static void testDuplicate_withinSixMonths() {
        Lead existing = new Lead(
            LastName           = '既存',
            Company            = '既存会社',
            Email              = 'dup@example.com',
            Phone              = '09011111111',
            LeadSourceDate__c  = Date.today().addMonths(-3)
        );
        insert existing;

        Lead newLead = new Lead(
            LastName           = '新規',
            Company            = '新規会社',
            Email              = 'dup@example.com',
            Phone              = '09022222222',
            LeadSourceDate__c  = Date.today()
        );
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.duplicateRuleHeader.allowSave = true;
        Database.insert(newLead, dml);

        Lead newResult = [SELECT Status FROM Lead WHERE Id = :newLead.Id];
        System.assertEquals('アーカイブ', newResult.Status);

        Lead existingResult = [SELECT Remarks__c FROM Lead WHERE Id = :existing.Id];
        System.assert(existingResult.Remarks__c != null);
        System.assert(existingResult.Remarks__c.contains('重複'));
    }

    @isTest
    static void testReflow_overSixMonths() {
        Lead existing = new Lead(
            LastName           = '既存',
            Company            = '既存会社',
            Email              = 'reflow@example.com',
            Phone              = '09033333333',
            LeadSourceDate__c  = Date.today().addMonths(-8)
        );
        insert existing;

        Lead newLead = new Lead(
            LastName           = '新規',
            Company            = '新規会社',
            Email              = 'reflow@example.com',
            Phone              = '09044444444',
            LeadSourceDate__c  = Date.today()
        );
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.duplicateRuleHeader.allowSave = true;
        Database.insert(newLead, dml);

        Lead newResult = [SELECT Status FROM Lead WHERE Id = :newLead.Id];
        System.assertEquals('アーカイブ', newResult.Status);

        Lead existingResult = [SELECT Remarks__c FROM Lead WHERE Id = :existing.Id];
        System.assert(existingResult.Remarks__c != null);
        System.assert(existingResult.Remarks__c.contains('再流入'));
    }
}