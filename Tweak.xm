#import <UIKit/UIKit.h>

// 声明 iOS 底层私有方法，防止编译报错
@interface SBIconListView : UIView
- (NSString *)iconLocation;
@end

@interface SBIconListModel : NSObject
- (void)setFixedLocation:(unsigned long long)location forIcon:(id)icon;
@end

// ===================================================================
// 1. 视图层 (View Layer)：允许桌面网格存在空隙
// ===================================================================
%hook SBIconListView

- (BOOL)allowsGaps {
    if ([self respondsToSelector:@selector(iconLocation)]) {
        NSString *location = [self iconLocation];
        // 核心防御：绝对不能让底部的 Dock 栏允许空隙，否则 Dock 会排版错乱
        if (location && [location containsString:@"Dock"]) {
            return %orig;
        }
    }
    return YES; // 让普通的桌面视图全面支持留空
}

%end


// ===================================================================
// 2. 数据层 (Model Layer)：接管并锁死系统原生的位置记录
// ===================================================================
%hook SBIconListModel

// 允许数据模型开启"固定图标位置"功能
- (BOOL)allowsFixedIconLocations {
    return YES;
}

// 强制开启系统底层的固定位置行为 (1 = Enabled)
- (long long)fixedIconLocationBehavior {
    return 1;
}

// 【核心防御 1】：防止系统偷偷清空我们的自定义位置
- (void)removeAllFixedIconLocations {
    // 留空，拦截系统的全局清除，保护我们的自定义排版
}

- (void)removeFixedIconLocationsForIcons:(id)icons {
    // 留空，防止批量清除
}

// 【核心防御 2】：告诉系统，图标放到哪里就是哪里，不要自动往前面吸附！
- (unsigned long long)bestGridCellIndexForInsertingIcon:(id)icon atGridCellIndex:(unsigned long long)index {
    return index;
}

- (unsigned long long)bestGridCellIndexForInsertingIcon:(id)icon atGridCellIndex:(unsigned long long)index gridCellInfoOptions:(unsigned long long)options {
    return index;
}

// 【核心防御 3】：瘫痪系统的网格挤压修补算法
- (void)compactIcons {
    // 留空，拒绝压缩靠拢
}

// ⚠️ 极其关键：必须返回传入的 icons 或者 @[]，绝对不能返回 nil/self 导致 NSArray 崩溃！
- (id)_updateModelByRepairingGapsIfNecessary {
    return @[]; 
}

- (id)_updateModelByRepairingGapsIfNecessaryAvoidingIcons:(id)icons {
    return @[]; 
}

- (id)repairModelByEliminatingGapsInIcons:(id)icons avoidingIcons:(id)avoidingIcons {
    // 原样返回，坚决不清除空隙，同时满足底层 NSMutableSet 接收 NSArray 的类型要求
    return icons ? icons : @[];
}

// 【核心防御 4】：在新增和移动图标时，主动把坐标写入系统的“固定坐标字典”里！
- (id)insertIcon:(id)icon atGridCellIndex:(unsigned long long)index gridCellInfoOptions:(unsigned long long)options mutationOptions:(unsigned long long)mutOptions {
    id result = %orig;
    if (icon && [self respondsToSelector:@selector(setFixedLocation:forIcon:)]) {
        [self setFixedLocation:index forIcon:icon]; // 落地生根
    }
    return result;
}

- (id)moveContainedIcon:(id)icon toGridCellIndex:(unsigned long long)index gridCellInfoOptions:(unsigned long long)options mutationOptions:(unsigned long long)mutOptions {
    id result = %orig;
    if (icon && [self respondsToSelector:@selector(setFixedLocation:forIcon:)]) {
        [self setFixedLocation:index forIcon:icon]; // 落地生根
    }
    return result;
}

%end
