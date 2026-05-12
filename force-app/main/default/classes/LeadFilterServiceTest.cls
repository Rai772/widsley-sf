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
    static void testSpam_invalidPhone_meetsmore() {
        Lead lead = new Lead(
            LastName            = 'テスト2',
            Company             = 'テスト会社',
            Email               = 'test2@example.com',
            Phone               = '123',
            first_touchpoint__c = 'ミツモア'
        );
        insert lead;

        Lead result = [SELECT Status, first_touchpoint__c FROM Lead WHERE Id = :lead.Id];
        System.assertEquals('アーカイブ', result.Status);
        System.assertEquals('ミツモア（逆営業と無効）', result.first_touchpoint__c);
    }

    @isTest
    static void testSpam_validPhone() {
        Lead lead = new Lead(
            LastName = 'テスト3',
            Company  = 'テスト会社',
            Email    = 'test3@example.com',
            Phone    = '09012345678'
        );
        insert lead;

        Lead result = [SELECT Status FROM Lead WHERE Id = :lead.Id];
        System.assertNotEquals('アーカイブ', result.Status);
    }

    @isTest
    static void testSpam_blankPhone() {
        Lead lead = new Lead(
            LastName            = 'テスト4',
            Company             = 'テスト会社',
            Email               = 'test4@example.com',
            Phone               = '',
            first_touchpoint__c = 'ミツモア'
        );
        insert lead;

        Lead result = [SELECT Status, first_touchpoint__c FROM Lead WHERE Id = :lead.Id];
        System.assertEquals('アーカイブ', result.Status);
        System.assertEquals('ミツモア（逆営業と無効）', result.first_touchpoint__c);
    }
}