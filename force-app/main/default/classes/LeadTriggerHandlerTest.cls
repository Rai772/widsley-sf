@isTest
public class LeadTriggerHandlerTest {

    @isTest
    static void testAfterInsert_spamLead_meetsmore() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse());
        Lead lead = new Lead(
            LastName            = 'スパムテスト',
            Company             = 'テスト会社',
            Email               = 'spam@example.com',
            Phone               = '123',
            first_touchpoint__c = 'ミツモア'
        );
        Test.startTest();
        insert lead;
        Test.stopTest();

        Lead result = [SELECT Status, first_touchpoint__c FROM Lead WHERE Id = :lead.Id];
        System.assertEquals('アーカイブ', result.Status);
        System.assertEquals('ミツモア（逆営業と無効）', result.first_touchpoint__c);
    }

    @isTest
    static void testAfterInsert_validLead() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse());

        User adminUser = [
            SELECT Id FROM User
            WHERE Name = 'Widsley Admin'
            AND IsActive = true
            LIMIT 1
        ];

        Lead lead = new Lead(
            LastName = '有効テスト',
            Company  = 'テスト会社',
            Email    = 'valid@example.com',
            Phone    = '09012345678',
            User__c  = adminUser.Id
        );
        Test.startTest();
        insert lead;
        Test.stopTest();

        Lead result = [SELECT IsConverted FROM Lead WHERE Id = :lead.Id];
        System.assertEquals(true, result.IsConverted, 'リードが取引開始されていること');
    }

    @isTest
    static void testAfterInsert_noTouchpoint() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse());
        Lead lead = new Lead(
            LastName = 'タッチポイントなし',
            Company  = 'テスト会社',
            Email    = 'notouchpoint@example.com',
            Phone    = '000'
        );
        Test.startTest();
        insert lead;
        Test.stopTest();

        Lead result = [SELECT Status, first_touchpoint__c FROM Lead WHERE Id = :lead.Id];
        System.assertEquals('アーカイブ', result.Status);
        System.assertEquals('逆営業と無効', result.first_touchpoint__c);
    }

    @isTest
    static void testAfterInsert_existingCustomer() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse());

        User adminUser = [
            SELECT Id FROM User
            WHERE Name = 'Widsley Admin'
            AND IsActive = true
            LIMIT 1
        ];

        Account acc = new Account(Name = 'テスト取引先');
        insert acc;

        Opportunity opp = new Opportunity(
            Name      = 'テスト商談',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addMonths(1)
        );
        insert opp;

        Contract__c contract = new Contract__c(
            AccountId__c        = acc.Id,
            first_oppotunity__c = opp.Id
        );
        insert contract;

        Contact contact = new Contact(
            LastName  = '既存顧客',
            AccountId = acc.Id,
            Email     = 'existing@example.com'
        );
        insert contact;

        Lead lead = new Lead(
            LastName = '既存顧客テスト',
            Company  = 'テスト会社',
            Email    = 'existing@example.com',
            Phone    = '09011112222',
            User__c  = adminUser.Id
        );
        Test.startTest();
        insert lead;
        Test.stopTest();

        Lead result = [SELECT IsExistingCustomer__c FROM Lead WHERE Id = :lead.Id];
        System.assertEquals(true, result.IsExistingCustomer__c, '既存顧客フラグがtrueであること');
    }

    @isTest
    static void testAfterInsert_duplicateLead() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse());

        User adminUser = [
            SELECT Id FROM User
            WHERE Name = 'Widsley Admin'
            AND IsActive = true
            LIMIT 1
        ];

        Lead existing = new Lead(
            LastName          = '既存重複',
            Company           = 'テスト会社',
            Email             = 'duplicate@example.com',
            Phone             = '000',
            LeadSourceDate__c = Date.today().addMonths(-3),
            User__c           = adminUser.Id
        );
        insert existing;

        Lead newLead = new Lead(
            LastName          = '新規重複',
            Company           = 'テスト会社',
            Email             = 'duplicate@example.com',
            Phone             = '09011112222',
            LeadSourceDate__c = Date.today(),
            User__c           = adminUser.Id
        );
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.duplicateRuleHeader.allowSave = true;
        Test.startTest();
        Database.insert(newLead, dml);
        Test.stopTest();

        Lead existingResult = [SELECT IsDuplicate__c FROM Lead WHERE Id = :existing.Id];
        System.assertEquals(true, existingResult.IsDuplicate__c, '既存リードに重複フラグがセットされていること');

        Lead newResult = [SELECT Status FROM Lead WHERE Id = :newLead.Id];
        System.assertEquals('アーカイブ', newResult.Status, '新リードがアーカイブになっていること');
    }
}