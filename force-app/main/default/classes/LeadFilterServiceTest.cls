@isTest
public class LeadFilterServiceTest {

    @isTest
    static void testSpam_invalidPhone_aspic() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse());
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
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse());
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
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse());
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
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse());
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

    @isTest
    static void testExistingCustomer() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse());
    
        Account acc = new Account(Name = 'テスト取引先');
        insert acc;
    
        Contact con = new Contact(
            LastName  = 'テスト',
            AccountId = acc.Id,
            Email     = 'existing@example.com',
            Phone     = '09055555555'
        );
        insert con;
    
        Opportunity opp = new Opportunity(
            Name       = 'テスト商談',
            AccountId  = acc.Id,
            Contact__c = con.Id,
            StageName  = 'ISナーチャリング',
            CloseDate  = Date.today()
        );
        insert opp;
        opp.StageName = 'アポイント設定';
        update opp;
        opp.StageName = '商談実施';
        update opp;
        opp.StageName = '商談化';
        update opp;
        opp.StageName = '担当者合意';
        update opp;
        opp.StageName = '決裁者合意';
        update opp;
        opp.StageName = 'フォームの回収';
        update opp;
        opp.StageName = '成約';
        update opp;
    
        Lead lead = new Lead(
            LastName = '既存顧客',
            Company  = 'テスト会社',
            Email    = 'existing@example.com',
            Phone    = '09066666666'
        );
    
        Test.startTest();
        insert lead;
        Test.stopTest();
    
        Lead result = [SELECT IsExistingCustomer__c FROM Lead WHERE Id = :lead.Id];
        System.assertEquals(true, result.IsExistingCustomer__c);
    }
}