import { FormExtensionAbility, formBindingData } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'DeepSeekForm';

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    hilog.info(DOMAIN, TAG, 'onAddForm');
    return formBindingData.createFormBindingData({});
  }

  onCastToNormalForm(formId: string): void {
    hilog.info(DOMAIN, TAG, 'onCastToNormalForm %{public}s', formId);
  }

  onUpdateForm(formId: string): void {
    hilog.info(DOMAIN, TAG, 'onUpdateForm %{public}s', formId);
  }

  onChangeFormVisibility(newStatus: Record<string, number>): void {
    hilog.info(DOMAIN, TAG, 'onChangeFormVisibility');
  }

  onRemoveForm(formId: string): void {
    hilog.info(DOMAIN, TAG, 'onRemoveForm %{public}s', formId);
  }
}
