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
        Lead lead = new Lead(
            LastName = '有効テスト',
            Company  = 'テスト会社',
            Email    = 'valid@example.com',
            Phone    = '09012345678'
        );
        Test.startTest();
        insert lead;
        Test.stopTest();

        Lead result = [SELECT Status FROM Lead WHERE Id = :lead.Id];
        System.assertNotEquals('アーカイブ', result.Status);
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
}