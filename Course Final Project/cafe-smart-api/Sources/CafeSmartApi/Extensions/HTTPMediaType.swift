//
//  HTTPMediaType.swift
//  CafeSmartApi
//
//  Created by Cole M on 8/26/25.
//
import Vapor

extension HTTPMediaType {
  public static var binaryCodable: HTTPMediaType {
    HTTPMediaType(type: "application", subType: "x-binary-codable")
  }
}
